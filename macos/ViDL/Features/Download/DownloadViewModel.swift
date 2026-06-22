import SwiftUI
import AppKit
import Observation

// MARK: - Transfer state machine
//
// The footer/progress UI used to be spread across ~13 mutually-dependent flags
// (downloading, encoding, footerActive, justDownloaded, showReencode, progress,
// statusText, percentText…). That made illegal combinations representable and was
// the root of the "footer jumps / not cleared / wrong video" bugs. It's now a single
// source of truth — `phase: TransferPhase` — from which all presentation is *derived*.

/// Pre-first-byte stages, surfaced so the indeterminate bar doesn't look stuck.
/// Ranked so labels only ever move forward (yt-dlp interleaves [info] lines).
enum PrepPhase: Int, Comparable {
    case cookies = -1        // age-restricted retry with Firefox cookies
    case starting = 0        // generic "Preparing…"
    case fetchingInfo = 1
    case verifying = 2
    case preparingStream = 3
    static func < (a: PrepPhase, b: PrepPhase) -> Bool { a.rawValue < b.rawValue }
}

enum FinalizeKind: Equatable { case merging, extracting }

/// Immutable identity of a download, captured at start so a concurrent re-analysis
/// (which mutates `meta`) can't make the completion handler mislabel the file.
struct DownloadSnapshot: Equatable {
    let title: String?
    let url: String
    let thumbnailURL: String?
    let exportType: ExportType
}

/// Maps yt-dlp's per-stream 0→100 onto a global bar. Segment boundaries come from
/// "[download] Destination:" lines (reliable), not the non-monotonic percentage.
struct SegmentTracker: Equatable {
    var expected = 1
    var current = 0
    var fileCount = 0
    var skipNextPct = true   // drops yt-dlp's spurious first reading of each stream
    var rawPct = 0.0         // monotonic raw % within the current stream
}

/// Live data of an in-flight download. Carried inside the phase so it can't outlive
/// the job (no stale percent/speed after completion) and travels with its identity.
struct Transfer: Equatable {
    let snapshot: DownloadSnapshot
    let outputPath: String
    var progress: Double = 0
    var percentText: String = ""
    var speedText: String = ""
    var etaText: String = ""
    var filePath: String?
    var segments = SegmentTracker()
}

/// Result of a finished download.
struct Completion: Equatable {
    let snapshot: DownloadSnapshot
    let filePath: String?
    let sizeMB: Double?
    var offersReencode: Bool { snapshot.exportType == .mp4 && filePath != nil }
}

enum TransferPhase: Equatable {
    /// No active or finished job to show → footer absent.
    case none

    case preparing(PrepPhase, Transfer)        // before first byte → indeterminate bar
    case downloading(Transfer)                 // bytes flowing → determinate 0…100
    case finalizing(FinalizeKind, Transfer)    // yt-dlp muxing / extracting

    case completed(Completion)
    case failed(String)
    case cancelled

    case reencoding(Double)
    case reencoded(String)                     // path of the re-encoded file
    case reencodeFailed(String)
}

extension TransferPhase {
    /// The in-flight transfer, if the current phase carries one.
    var transfer: Transfer? {
        switch self {
        case .preparing(_, let t), .downloading(let t), .finalizing(_, let t): return t
        default: return nil
        }
    }

    var footerVisible: Bool { self != .none }

    var showsIndeterminate: Bool {
        if case .preparing = self { return true }
        return false
    }

    /// The real target the eased `displayProgress` chases (0…100).
    var targetProgress: Double {
        switch self {
        case .preparing(_, let t), .downloading(let t), .finalizing(_, let t): return t.progress
        case .completed, .reencoded:        return 100
        case .reencoding(let p):            return p
        case .none, .failed, .cancelled, .reencodeFailed: return 0
        }
    }

    /// A process is running → disable "Download", keep the eased bar alive.
    var isBusy: Bool {
        switch self {
        case .preparing, .downloading, .finalizing, .reencoding: return true
        default: return false
        }
    }

    /// A download (not a re-encode) is in flight → show "Cancel".
    var isTransferring: Bool {
        switch self {
        case .preparing, .downloading, .finalizing: return true
        default: return false
        }
    }

    var isReencoding: Bool {
        if case .reencoding = self { return true }
        return false
    }

    /// A finished job whose footer we keep on screen, ready to be emptied on re-analysis.
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled, .reencoded, .reencodeFailed: return true
        default: return false
        }
    }

    /// File available to reveal in the Finder (only after a successful job).
    var revealableFile: String? {
        switch self {
        case .completed(let c): return c.filePath
        case .reencoded(let p): return p
        default:                return nil
        }
    }

    var offersReencode: Bool {
        switch self {
        case .completed(let c): return c.offersReencode
        case .reencoded:        return true   // re-available after a first re-encode
        default:                return false
        }
    }
}

@Observable
@MainActor
final class DownloadViewModel {
    var url: String = ""
    var analyzing = false
    var analysisInfo = ""

    var meta: VideoMeta?
    var videoFormats: [VideoFormat] = []
    var audioFormats: [AudioFormat] = []

    var exportType: ExportType = .mp4
    var selectedVideoFormatID: String?
    var audioLanguage = "Auto"
    /// Output MP3 bitrate (kbps). MP3 always re-encodes the best source audio, so this
    /// is what actually controls quality — not which source stream is picked.
    var mp3Bitrate: String = UserDefaults.standard.string(forKey: "mp3Bitrate") ?? "320" {
        didSet { UserDefaults.standard.set(mp3Bitrate, forKey: "mp3Bitrate") }
    }

    // Clip / time-range download (yt-dlp --download-sections).
    var clipEnabled = false
    var clipStart = "00:00"
    var clipEnd = ""
    var clipPreciseCut = false   // --force-keyframes-at-cuts: exact bounds, re-encodes edges

    private static var defaultDownloads: String {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory() + "/Downloads"
    }
    var outputDirPath: String = UserDefaults.standard.string(forKey: "outputDirPath") ?? DownloadViewModel.defaultDownloads {
        didSet { UserDefaults.standard.set(outputDirPath, forKey: "outputDirPath") }
    }
    var openFolderAfter: Bool = (UserDefaults.standard.object(forKey: "openFolderAfter") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(openFolderAfter, forKey: "openFolderAfter") }
    }

    /// Single source of truth for everything the footer/progress shows.
    var phase: TransferPhase = .none
    /// Eased value the bar actually draws (~60fps), chasing `phase.targetProgress`.
    var displayProgress: Double = 0
    /// The last successful download, kept so the on-screen card can show "Downloaded"
    /// only while it still displays that very video.
    private var lastCompletion: Completion?

    var errorMessage: String?
    private var lastErrorLine: String?

    var app: AppState?
    var settings: AppSettings?
    private func tr(_ fr: String, _ en: String) -> String { app?.tr(fr, en) ?? fr }

    static let audioLanguages = ["Auto", "en", "pl", "fr", "de", "es", "it", "pt", "ja", "ko", "zh-Hans", "zh-Hant"]
    static let mp3Bitrates = ["320", "256", "192", "128"]

    private var activeProcess: ManagedProcess?
    private var cancelled = false
    private var ageDetected = false
    private var cancelReencode = false
    private var smoothTask: Task<Void, Never>?

    // Info JSON captured at analysis, reused at download time to skip re-extraction.
    private var cachedInfoURL: String?
    private var cachedInfoPath: String?
    private static let infoJSONPath = NSTemporaryDirectory() + "vidl-last-info.json"

    // MARK: - Derived presentation

    /// The on-screen card's "Downloaded" mark: true only when the displayed video is
    /// the one we actually downloaded (the user may have analyzed a different URL since).
    var justDownloaded: Bool {
        guard let lastCompletion, let title = meta?.title else { return false }
        return lastCompletion.snapshot.title == title
    }

    /// Footer status line, localized, derived entirely from `phase`.
    var statusLine: String {
        switch phase {
        case .none:                        return ""
        case .preparing(.cookies, _):      return tr("Vidéo restreinte → cookies Firefox…", "Age-restricted → Firefox cookies…")
        case .preparing(.starting, _):     return tr("Préparation…", "Preparing…")
        case .preparing(.fetchingInfo, _): return tr("Récupération des informations…", "Fetching video info…")
        case .preparing(.verifying, _):    return tr("Vérification YouTube…", "Verifying with YouTube…")
        case .preparing(.preparingStream, _): return tr("Préparation du flux…", "Preparing stream…")
        case .downloading:                 return tr("Téléchargement…", "Downloading…")
        case .finalizing(.merging, _):     return tr("Fusion des pistes…", "Merging streams…")
        case .finalizing(.extracting, _):  return tr("Extraction audio…", "Extracting audio…")
        case .completed(let c):
            let sz = c.sizeMB.map { String(format: " (%.1f MB)", $0) } ?? ""
            return tr("Téléchargement terminé\(sz).", "Download complete\(sz).")
        case .failed(let m):               return m
        case .cancelled:                   return tr("Téléchargement arrêté. Fichiers incomplets supprimés.",
                                                     "Download stopped. Incomplete files removed.")
        case .reencoding(let p):           return String(format: tr("Ré-encodage… %.1f %%", "Re-encoding… %.1f%%"), p)
        case .reencoded:                   return tr("Fichier MP4 ré-encodé et optimisé.", "MP4 re-encoded and optimized.")
        case .reencodeFailed(let m):       return m
        }
    }

    /// Footer detail line (%/speed/ETA), present only during an active transfer.
    var detailLine: String {
        guard let t = phase.transfer else { return "" }
        var parts: [String] = []
        if !t.percentText.isEmpty { parts.append(t.percentText) }
        if !t.speedText.isEmpty { parts.append(t.speedText) }
        if !t.etaText.isEmpty { parts.append("ETA \(t.etaText)") }
        return parts.joined(separator: " · ")
    }

    /// Mutates the in-flight transfer in place (no-op outside transfer phases).
    private func withTransfer(_ body: (inout Transfer) -> Void) {
        switch phase {
        case .preparing(let p, var t): body(&t); phase = .preparing(p, t)
        case .downloading(var t):      body(&t); phase = .downloading(t)
        case .finalizing(let k, var t): body(&t); phase = .finalizing(k, t)
        default: break
        }
    }

    // MARK: - Smooth progress follower

    /// Continuously eases `displayProgress` toward `phase.targetProgress` (~60fps),
    /// like the original app. If progress stalls, the bar catches up and quietly stops.
    private func startSmoothing() {
        smoothTask?.cancel()
        smoothTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                if self.tickSmoothing() { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    /// Returns true when smoothing should stop (converged and nothing running).
    private func tickSmoothing() -> Bool {
        let target = phase.targetProgress
        let diff = target - displayProgress
        if abs(diff) < 0.1 {
            displayProgress = target
            return !phase.isBusy
        }
        // Same easing rhythm as the original app (step = diff * 0.2 @ 20fps → τ ≈ 0.22s).
        displayProgress += diff * 0.073
        return false
    }

    var hasMissingBinaries: Bool { BinaryLocator.ytDlp == nil }
    /// ffmpeg is needed to merge video+audio for MP4 and to extract MP3 — warn even
    /// when yt-dlp is present, otherwise the failure only surfaces mid-download.
    var hasMissingFFmpeg: Bool { BinaryLocator.ffmpeg == nil }

    // MARK: - Analyze

    func analyze() async {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = tr("Entrez l'URL d'une page contenant une vidéo.",
                              "Enter the URL of a page containing a video.")
            return
        }
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            errorMessage = tr("URL invalide (http:// ou https://).", "Invalid URL (http:// or https://).")
            return
        }
        guard BinaryLocator.ytDlp != nil else {
            errorMessage = tr("yt-dlp introuvable. Installez-le via Homebrew : brew install yt-dlp",
                              "yt-dlp not found. Install it with Homebrew: brew install yt-dlp")
            return
        }

        analyzing = true
        analysisInfo = ""
        meta = nil
        videoFormats = []
        audioFormats = []
        selectedVideoFormatID = nil
        cachedInfoURL = nil
        cachedInfoPath = nil
        // A new analysis means moving on to another video — clear the previous job's
        // footer entirely (an empty bar would say nothing, and a stale "done" message
        // would be misleading). No-op while a job runs: that transfer still owns the
        // footer (the analyze-during-download case).
        if phase.isTerminal {
            phase = .none
            displayProgress = 0
        }

        var (result, ageRestricted, infoJSON, error) = await YTDLPService.analyze(url: trimmed)
        var usedCookies = false
        if result == nil && ageRestricted, let browser = settings?.cookiesBrowser.ytDlpValue {
            (result, _, infoJSON, error) = await YTDLPService.analyze(url: trimmed, cookiesBrowser: browser)
            usedCookies = true
        }

        analyzing = false
        guard let result else {
            let msg = analyzeErrorText(error)
            analysisInfo = msg       // stays visible after the alert is dismissed
            errorMessage = msg       // surfaces the real cause instead of a vague grey line
            return
        }
        meta = result.meta
        videoFormats = result.videoFormats
        audioFormats = result.audioFormats
        analysisInfo = tr("\(result.videoFormats.count) formats vidéo · \(result.audioFormats.count) audio",
                          "\(result.videoFormats.count) video formats · \(result.audioFormats.count) audio")
        selectDefaultFormat()
        clipStart = "00:00"
        if let d = result.meta.duration, d > 0 { clipEnd = Formatting.duration(d) } else { clipEnd = "" }

        // Cache the extracted info so the download can skip re-extraction (big prep
        // speedup). No-cookie happy path only; age-restricted media uses normal extraction.
        if !usedCookies, let infoJSON, let data = infoJSON.data(using: .utf8),
           (try? data.write(to: URL(fileURLWithPath: Self.infoJSONPath))) != nil {
            cachedInfoURL = trimmed
            cachedInfoPath = Self.infoJSONPath
        }
    }

    private func selectDefaultFormat() {
        guard exportType == .mp4 else { return }   // MP3 quality is the output bitrate, not a source stream
        // Prefer 1080p, else 720p, else best (last).
        var chosen = videoFormats.last?.id
        for f in videoFormats {
            let h = min(f.height, f.width)
            if h == 1080 { chosen = f.id; break }
            if h == 720 { chosen = f.id }
        }
        selectedVideoFormatID = chosen
    }

    private func analyzeErrorText(_ error: AnalyzeError?) -> String {
        switch error {
        case .ageRestricted:
            return tr("Vidéo avec restriction d'âge. Choisissez un navigateur connecté à YouTube dans les Réglages.",
                      "Age-restricted video. Pick a browser signed into YouTube in Settings.")
        case .privateVideo:    return tr("Vidéo privée.", "Private video.")
        case .membersOnly:     return tr("Vidéo réservée aux membres.", "Members-only video.")
        case .unavailable:     return tr("Vidéo indisponible ou supprimée.", "Video unavailable or removed.")
        case .geoBlocked:      return tr("Vidéo non disponible dans votre pays.", "Video not available in your country.")
        case .notFound:        return tr("Vidéo introuvable (404).", "Video not found (404).")
        case .network:         return tr("Problème de connexion réseau.", "Network connection problem.")
        case .unsupportedURL:  return tr("URL non prise en charge.", "Unsupported URL.")
        case .notYetAvailable: return tr("Vidéo pas encore disponible (première ou live programmé).",
                                         "Video not available yet (premiere or scheduled live).")
        case .signInRequired:  return tr("Connexion requise. Choisissez un navigateur pour les cookies dans les Réglages.",
                                         "Sign-in required. Pick a cookies browser in Settings.")
        case .other(let msg) where !msg.isEmpty: return msg
        default:               return tr("Aucun format exploitable trouvé.", "No usable formats found.")
        }
    }

    func onExportTypeChange() { selectDefaultFormat() }

    // MARK: - Download

    func download(history: HistoryStore) async {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.hasPrefix("http") else {
            errorMessage = tr("URL manquante ou invalide.", "Missing or invalid URL.")
            return
        }
        guard let ytDlp = BinaryLocator.ytDlp else {
            errorMessage = tr("yt-dlp introuvable.", "yt-dlp not found.")
            return
        }

        let formatID: String
        if exportType == .mp4 {
            guard let id = selectedVideoFormatID else { errorMessage = tr("Analysez la vidéo d'abord.", "Analyze the video first."); return }
            formatID = id
        } else {
            guard meta != nil else { errorMessage = tr("Analysez la vidéo d'abord.", "Analyze the video first."); return }
            formatID = ""   // MP3 uses best-audio selection in the service
        }

        let snapshot = DownloadSnapshot(title: meta?.title, url: trimmed,
                                        thumbnailURL: meta?.thumbnailURL, exportType: exportType)

        let raw = Formatting.sanitizeFilename(meta?.title ?? "video")
        let stem = raw.isEmpty ? "video" : raw
        // Suffix is a marker for downstream tools (e.g. Quarry's downloads sorter
        // exempts files containing "_vidl"). When yt-dlp surfaces the channel
        // handle, append it after the marker so the source channel is visible
        // in the filename: "<title>_vidl_@handle.ext".
        let handle = Formatting.sanitizeFilename(meta?.channelHandle ?? "")
        let base = handle.isEmpty ? stem + "_vidl" : stem + "_vidl_" + handle
        let ext = exportType == .mp4 ? "mp4" : "mp3"
        let outputPath = uniquePath(dir: outputDirPath, base: base, ext: ext)

        var clipSection: String?
        if clipEnabled {
            guard let s = parseTime(clipStart), let e = parseTime(clipEnd), e > s else {
                errorMessage = tr("Plage d'extrait invalide (début < fin, format mm:ss).",
                                  "Invalid clip range (start < end, mm:ss).")
                return
            }
            clipSection = "*\(clipStart)-\(clipEnd)"
        }

        lastErrorLine = nil
        cancelled = false
        ageDetected = false
        displayProgress = 0
        let expected = formatID.contains("+") ? 2 : 1

        func beginPreparing(_ prep: PrepPhase) {
            var t = Transfer(snapshot: snapshot, outputPath: outputPath)
            t.segments.expected = expected
            phase = .preparing(prep, t)
        }
        func buildArgs(cookiesBrowser: String?, infoJSONPath: String?) -> [String] {
            YTDLPService.downloadArguments(url: trimmed, formatID: formatID,
                                           exportType: exportType, audioLanguage: audioLanguage,
                                           mp3Bitrate: mp3Bitrate, outputPath: outputPath,
                                           cookiesBrowser: cookiesBrowser, infoJSONPath: infoJSONPath,
                                           downloadSection: clipSection, forceKeyframes: clipPreciseCut)
        }

        beginPreparing(.starting)
        startSmoothing()

        var status: Int32 = -1

        // Fast path: reuse the JSON captured at analysis to skip re-extraction (prep
        // becomes near-instant). Any failure falls through to a fresh extraction.
        if cachedInfoURL == trimmed, let infoPath = cachedInfoPath,
           FileManager.default.fileExists(atPath: infoPath) {
            status = await runDownload(executable: ytDlp, args: buildArgs(cookiesBrowser: nil, infoJSONPath: infoPath))
            if status != 0 && !cancelled {
                ageDetected = false        // cached info likely stale → restart clean
                beginPreparing(.starting)
            }
        }

        // Normal extraction (also the fallback when the cached info failed).
        if status != 0 && !cancelled {
            status = await runDownload(executable: ytDlp, args: buildArgs(cookiesBrowser: nil, infoJSONPath: nil))
        }

        // Age-restricted retry using the configured browser's cookies.
        if status != 0 && ageDetected && !cancelled, let browser = settings?.cookiesBrowser.ytDlpValue {
            ageDetected = false
            beginPreparing(.cookies)
            status = await runDownload(executable: ytDlp, args: buildArgs(cookiesBrowser: browser, infoJSONPath: nil))
        }

        activeProcess = nil

        if status == 0 {
            finishSuccess(history: history, snapshot: snapshot)
        } else if cancelled {
            cleanupIncompleteFiles(outputPath: outputPath)
            phase = .cancelled
        } else {
            phase = .failed(tr("Échec du téléchargement.", "Download failed."))
            errorMessage = cleanedError() ?? tr("Échec du téléchargement.", "Download failed.")
        }
    }

    /// Removes the partial output and yt-dlp's intermediate per-stream files
    /// (`<stem>.f<id>.<ext>`, `.part`, `.ytdl`) left behind when the download is cancelled.
    /// Safe because the `_vidl` suffix plus `uniquePath()` make the stem unique to this run.
    private func cleanupIncompleteFiles(outputPath: String) {
        let fm = FileManager.default
        let dir = (outputPath as NSString).deletingLastPathComponent
        let stem = ((outputPath as NSString).deletingPathExtension as NSString).lastPathComponent
        guard !stem.isEmpty, let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
        for name in names where name == stem || name.hasPrefix(stem + ".") {
            try? fm.removeItem(atPath: "\(dir)/\(name)")
        }
    }

    /// Turns yt-dlp's raw "ERROR: [youtube] id: message" into a readable sentence.
    private func cleanedError() -> String? {
        guard var msg = lastErrorLine else { return nil }
        if let range = msg.range(of: #"^\[[^\]]+\]\s*[^:]*:\s*"#, options: .regularExpression) {
            msg.removeSubrange(range)
        }
        msg = msg.trimmingCharacters(in: .whitespacesAndNewlines)
        return msg.isEmpty ? nil : msg
    }

    private func runDownload(executable: String, args: [String]) async -> Int32 {
        let proc = ManagedProcess()
        activeProcess = proc
        return await proc.stream(executable: executable, arguments: args) { [weak self] line in
            self?.handleDownloadLine(line)
        }
    }

    private func handleDownloadLine(_ line: String) {
        if line.contains("Sign in to confirm") || line.lowercased().contains("age-restricted") {
            ageDetected = true
        }
        // Each new stream starts with a "[download] Destination:" line — a reliable segment boundary.
        if line.hasPrefix("[download] Destination: ") {
            withTransfer { t in
                t.segments.fileCount += 1
                t.segments.current = min(max(t.segments.fileCount - 1, 0), t.segments.expected - 1)
                t.segments.rawPct = 0
                t.segments.skipNextPct = true
            }
        }
        if line.hasPrefix("ERROR:") {
            lastErrorLine = String(line.dropFirst("ERROR:".count)).trimmingCharacters(in: .whitespaces)
        }
        if let m = firstGroup(#"at\s+([0-9.]+\s*[KMG]?i?B/s)"#, in: line) {
            withTransfer { $0.speedText = m.replacingOccurrences(of: " ", with: "") }
        }
        if let m = firstGroup(#"ETA\s+(\d+:\d+(?::\d+)?)"#, in: line) {
            withTransfer { $0.etaText = m }
        }
        if line.hasPrefix("[Merger]") {
            if let t = phase.transfer { phase = .finalizing(.merging, t) }
        } else if line.hasPrefix("[ExtractAudio]") {
            if let t = phase.transfer { phase = .finalizing(.extracting, t) }
        } else if case .preparing(let prep, let t) = phase {
            // Surface what yt-dlp is doing before the first byte; phases only move forward.
            let lower = line.lowercased()
            var next: PrepPhase?
            if lower.contains("solving") || lower.contains("challenge") {
                next = .verifying
            } else if lower.contains("m3u8") || lower.contains("manifest") || lower.contains("fragments") {
                next = .preparingStream
            } else if line.hasPrefix("[youtube]") || line.hasPrefix("[info]") {
                next = .fetchingInfo
            }
            if let next, next > prep { phase = .preparing(next, t) }
        }

        // Use yt-dlp's raw "%" (fine-grained, ~10/sec). Skip the spurious first reading of each
        // stream, keep it monotonic within the stream, and map onto the segment slice.
        if parsePercent(line) != nil {
            withTransfer { t in
                guard let pct = self.parsePercent(line) else { return }
                if t.segments.skipNextPct {
                    t.segments.skipNextPct = false
                } else {
                    if pct > t.segments.rawPct { t.segments.rawPct = pct }
                    let global = (Double(t.segments.current) * 100 + t.segments.rawPct) / Double(t.segments.expected)
                    if global > t.progress {
                        t.progress = global
                        t.percentText = String(format: "%5.1f %%", global)
                    }
                }
            }
            // First real byte while preparing → we're downloading (drops the indeterminate bar).
            if case .preparing(_, let t) = phase, t.progress > 0 {
                phase = .downloading(t)
            }
        }
        if let path = captureDestination(line) {
            withTransfer { $0.filePath = path }
        }
    }

    private func parsePercent(_ line: String) -> Double? {
        guard let range = line.range(of: #"\[download\]\s+([\d.]+)%"#, options: .regularExpression) else { return nil }
        let pctStr = String(line[range]).replacingOccurrences(of: "[download]", with: "")
            .trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
        return Double(pctStr)
    }

    private func firstGroup(_ pattern: String, in line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private func captureDestination(_ line: String) -> String? {
        for prefix in ["[download] Destination: ", "[ExtractAudio] Destination: "] {
            if line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        if let range = line.range(of: #"\[Merger\] Merging formats into "(.+)""#, options: .regularExpression) {
            let inner = String(line[range])
            if let q1 = inner.firstIndex(of: "\""), let q2 = inner.lastIndex(of: "\""), q1 != q2 {
                return String(inner[inner.index(after: q1)..<q2])
            }
        }
        return nil
    }

    private func finishSuccess(history: HistoryStore, snapshot: DownloadSnapshot) {
        let filePath = phase.transfer?.filePath
        var sizeMB: Double?
        if let path = filePath,
           let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Double {
            sizeMB = size / (1024 * 1024)
        }
        let completion = Completion(snapshot: snapshot, filePath: filePath, sizeMB: sizeMB)
        lastCompletion = completion
        phase = .completed(completion)
        Notifier.notifyIfBackgrounded(title: tr("Téléchargement terminé", "Download complete"),
                                      body: snapshot.title ?? "")

        if let title = snapshot.title, !title.isEmpty {
            let entry = HistoryEntry(title: title, url: snapshot.url,
                                     thumbnailURL: snapshot.thumbnailURL,
                                     downloadDate: Self.now(),
                                     filePath: filePath)
            history.add(entry)
        }
        if openFolderAfter { revealFolder() }
    }

    func cancelDownload() {
        cancelled = true
        activeProcess?.terminate()
        // The transition to .cancelled is made in download() when runDownload returns.
    }

    // MARK: - Re-encode for Final Cut Pro

    func reencode() async {
        if case .reencoding = phase {
            cancelReencode = true
            activeProcess?.terminate()
            return
        }
        guard let input = phase.revealableFile, FileManager.default.fileExists(atPath: input),
              let ffmpeg = BinaryLocator.ffmpeg else {
            errorMessage = tr("ffmpeg introuvable ou fichier absent.", "ffmpeg not found or file missing.")
            return
        }
        cancelReencode = false
        displayProgress = 0
        phase = .reencoding(0)
        startSmoothing()
        let output = input.replacingOccurrences(of: ".mp4", with: "_reencoded.mp4")
        let args = FFmpegService.reencodeArguments(input: input, output: output)
        let duration = meta?.duration ?? 0

        let proc = ManagedProcess()
        activeProcess = proc
        let status = await proc.stream(executable: ffmpeg, arguments: args) { [weak self] line in
            guard let self else { return }
            if duration > 0, let secs = FFmpegService.parseProgressSeconds(line) {
                self.phase = .reencoding(min(100, secs / duration * 100))
            }
            if self.cancelReencode { proc.terminate() }
        }
        activeProcess = nil

        if cancelReencode || status != 0 {
            try? FileManager.default.removeItem(atPath: output)
            phase = .reencodeFailed(cancelReencode ? tr("Ré-encodage annulé.", "Re-encoding cancelled.")
                                                   : tr("Erreur lors du ré-encodage.", "Error during re-encoding."))
        } else {
            // Swap the re-encoded file in for the original atomically. `replaceItemAt`
            // never deletes the original until the new file is in place, so a failure
            // (e.g. disk full) leaves the original intact instead of losing both files.
            do {
                _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: input),
                                                          withItemAt: URL(fileURLWithPath: output))
                phase = .reencoded(input)
            } catch {
                phase = .reencodeFailed(tr("Ré-encodage terminé, mais le remplacement du fichier a échoué. Le fichier d'origine est conservé.",
                                           "Re-encoding done, but replacing the file failed. The original file was kept."))
            }
        }
    }

    // MARK: - Thumbnail download

    func downloadThumbnail() {
        guard let urlString = meta?.thumbnailURL, let remote = URL(string: urlString) else {
            errorMessage = tr("Aucune miniature disponible.", "No thumbnail available.")
            return
        }
        let panel = NSSavePanel()
        let title = Formatting.sanitizeFilename(meta?.title ?? "thumbnail")
        let ext = (urlString.components(separatedBy: "?").first as NSString?)?.pathExtension ?? "jpg"
        panel.nameFieldStringValue = "\(title).\(ext.isEmpty ? "jpg" : ext)"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        Task {
            if let data = try? await URLSession.shared.data(from: remote).0 {
                try? data.write(to: dest)
            }
        }
    }

    // MARK: - Folders

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let dir = panel.url {
            outputDirPath = dir.path
        }
    }

    func revealFolder() {
        if let path = phase.revealableFile, FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: outputDirPath))
        }
    }

    // MARK: - Helpers

    /// Parses "ss", "mm:ss" or "hh:mm:ss" into seconds.
    private func parseTime(_ s: String) -> Double? {
        let parts = s.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, !parts.contains(where: { $0 == nil }) else { return nil }
        let nums = parts.compactMap { $0 }
        switch nums.count {
        case 1: return nums[0]
        case 2: return nums[0] * 60 + nums[1]
        case 3: return nums[0] * 3600 + nums[1] * 60 + nums[2]
        default: return nil
        }
    }

    private func uniquePath(dir: String, base: String, ext: String) -> String {
        let fm = FileManager.default
        var candidate = "\(dir)/\(base).\(ext)"
        var i = 1
        while fm.fileExists(atPath: candidate) {
            candidate = "\(dir)/\(base) (\(i)).\(ext)"
            i += 1
        }
        return candidate
    }

    private static func now() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date())
    }
}
