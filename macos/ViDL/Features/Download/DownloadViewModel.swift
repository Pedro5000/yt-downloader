import SwiftUI
import AppKit
import Observation

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
    var selectedAudioFormatID: String?
    var audioLanguage = "Auto"

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

    var downloading = false
    var progress: Double = 0          // real target driven by yt-dlp/ffmpeg
    var displayProgress: Double = 0   // eased value shown by the bar
    var statusText = ""
    var percentText = ""
    var speedText = ""
    var etaText = ""
    var downloadedFilePath: String?
    var showReencode = false
    var encoding = false

    var errorMessage: String?
    private var lastErrorLine: String?

    var app: AppState?
    private func tr(_ fr: String, _ en: String) -> String { app?.tr(fr, en) ?? fr }

    static let audioLanguages = ["Auto", "en", "pl", "fr", "de", "es", "it", "pt", "ja", "ko", "zh-Hans", "zh-Hant"]

    private var activeProcess: ManagedProcess?
    private var cancelled = false
    private var ageDetected = false
    private var cancelReencode = false

    // Multi-stream progress mapping (yt-dlp downloads each stream 0→100 separately).
    // Segment boundaries are detected from "[download] Destination:" lines, which reliably
    // mark each new stream — unlike the percentage, which is non-monotonic for fragmented DASH.
    private var expectedSegments = 1
    private var currentSegment = 0
    private var downloadFileCount = 0
    private var prepPhaseRank = 0
    private var skipNextPct = true       // drops yt-dlp's spurious first reading of each stream
    private var segmentRawPct = 0.0      // monotonic raw % within the current stream
    private var smoothTask: Task<Void, Never>?

    // MARK: - Smooth progress follower

    /// Continuously eases `displayProgress` toward `progress` (~60fps), like the original app.
    /// If the real progress stalls, the bar catches up and quietly stops.
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

    /// Returns true when smoothing should stop (converged and no operation running).
    private func tickSmoothing() -> Bool {
        let diff = progress - displayProgress
        if abs(diff) < 0.1 {
            displayProgress = progress
            return !downloading && !encoding
        }
        // Same easing rhythm as the original app (step = diff * 0.2 @ 20fps → τ ≈ 0.22s).
        displayProgress += diff * 0.073
        return false
    }

    var hasMissingBinaries: Bool { BinaryLocator.ytDlp == nil }

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
        selectedAudioFormatID = nil

        var (result, ageRestricted) = await YTDLPService.analyze(url: trimmed)
        if result == nil && ageRestricted {
            (result, _) = await YTDLPService.analyze(url: trimmed, useCookies: true)
        }

        analyzing = false
        guard let result else {
            analysisInfo = tr("Aucun format exploitable trouvé.", "No usable formats found.")
            return
        }
        meta = result.meta
        videoFormats = result.videoFormats
        audioFormats = result.audioFormats
        analysisInfo = tr("\(result.videoFormats.count) formats vidéo · \(result.audioFormats.count) audio",
                          "\(result.videoFormats.count) video formats · \(result.audioFormats.count) audio")
        selectDefaultFormat()
    }

    private func selectDefaultFormat() {
        if exportType == .mp4 {
            // Prefer 1080p, else 720p, else best (last).
            var chosen = videoFormats.last?.id
            for f in videoFormats {
                let h = min(f.height, f.width)
                if h == 1080 { chosen = f.id; break }
                if h == 720 { chosen = f.id }
            }
            selectedVideoFormatID = chosen
        } else {
            selectedAudioFormatID = audioFormats.first?.id
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
            guard let id = selectedAudioFormatID else { errorMessage = tr("Analysez la vidéo d'abord.", "Analyze the video first."); return }
            formatID = id
        }

        let base = Formatting.sanitizeFilename(meta?.title ?? "video")
        let ext = exportType == .mp4 ? "mp4" : "mp3"
        let outputPath = uniquePath(dir: outputDirPath, base: base.isEmpty ? "video" : base, ext: ext)

        downloadedFilePath = nil
        progress = 0
        displayProgress = 0
        speedText = ""
        etaText = ""
        percentText = ""
        lastErrorLine = nil
        startSmoothing()
        statusText = tr("Préparation…", "Preparing…")
        showReencode = false
        cancelled = false
        ageDetected = false
        downloading = true
        expectedSegments = formatID.contains("+") ? 2 : 1
        currentSegment = 0
        downloadFileCount = 0
        prepPhaseRank = 0
        skipNextPct = true
        segmentRawPct = 0

        let args = YTDLPService.downloadArguments(url: trimmed, formatID: formatID,
                                                  exportType: exportType, audioLanguage: audioLanguage,
                                                  outputPath: outputPath, useCookies: false)
        var status = await runDownload(executable: ytDlp, args: args)

        if status != 0 && ageDetected && !cancelled {
            statusText = tr("Vidéo restreinte → cookies Firefox…", "Age-restricted → Firefox cookies…")
            ageDetected = false
            progress = 0
            displayProgress = 0
            currentSegment = 0
            downloadFileCount = 0
            prepPhaseRank = 0
            skipNextPct = true
            segmentRawPct = 0
            let cookieArgs = YTDLPService.downloadArguments(url: trimmed, formatID: formatID,
                                                            exportType: exportType, audioLanguage: audioLanguage,
                                                            outputPath: outputPath, useCookies: true)
            status = await runDownload(executable: ytDlp, args: cookieArgs)
        }

        downloading = false
        activeProcess = nil
        speedText = ""
        etaText = ""
        percentText = ""

        if status == 0 {
            finishSuccess(history: history)
        } else if cancelled {
            statusText = tr("Téléchargement arrêté.", "Download stopped.")
            progress = 0
        } else {
            statusText = tr("Échec du téléchargement.", "Download failed.")
            progress = 0
            errorMessage = cleanedError() ?? tr("Échec du téléchargement.", "Download failed.")
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
            downloadFileCount += 1
            currentSegment = min(max(downloadFileCount - 1, 0), expectedSegments - 1)
            segmentRawPct = 0
            skipNextPct = true
        }
        if line.hasPrefix("ERROR:") {
            lastErrorLine = String(line.dropFirst("ERROR:".count)).trimmingCharacters(in: .whitespaces)
        }
        if let m = firstGroup(#"at\s+([0-9.]+\s*[KMG]?i?B/s)"#, in: line) {
            speedText = m.replacingOccurrences(of: " ", with: "")
        }
        if let m = firstGroup(#"ETA\s+(\d+:\d+(?::\d+)?)"#, in: line) {
            etaText = m
        }
        if line.hasPrefix("[Merger]") {
            statusText = tr("Fusion des pistes…", "Merging streams…")
        } else if line.hasPrefix("[ExtractAudio]") {
            statusText = tr("Extraction audio…", "Extracting audio…")
        } else if progress <= 0 {
            // Before the first byte: surface what yt-dlp is doing so the bar doesn't look stuck.
            // Phases are ranked and only ever move forward — yt-dlp interleaves [info] lines after
            // the manifest, which would otherwise make the label flicker backwards.
            let lower = line.lowercased()
            var rank = 0
            var text = ""
            if lower.contains("solving") || lower.contains("challenge") {
                rank = 2; text = tr("Vérification YouTube…", "Verifying with YouTube…")
            } else if lower.contains("m3u8") || lower.contains("manifest") || lower.contains("fragments") {
                rank = 3; text = tr("Préparation du flux…", "Preparing stream…")
            } else if line.hasPrefix("[youtube]") || line.hasPrefix("[info]") {
                rank = 1; text = tr("Récupération des informations…", "Fetching video info…")
            }
            if rank > prepPhaseRank {
                prepPhaseRank = rank
                statusText = text
            }
        }

        // Use yt-dlp's raw "%" (fine-grained, ~10/sec). Skip the spurious first reading of each
        // stream, keep it monotonic within the stream, and map onto the segment slice.
        if let pct = parsePercent(line) {
            if skipNextPct {
                skipNextPct = false
            } else {
                if pct > segmentRawPct { segmentRawPct = pct }
                let global = (Double(currentSegment) * 100 + segmentRawPct) / Double(expectedSegments)
                if global > progress {
                    progress = global
                    statusText = tr("Téléchargement…", "Downloading…")
                    percentText = String(format: "%5.1f %%", global)
                }
            }
        }
        if let path = captureDestination(line) { downloadedFilePath = path }
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

    private func finishSuccess(history: HistoryStore) {
        progress = 100
        var sizeMsg = ""
        if let path = downloadedFilePath,
           let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Double {
            sizeMsg = String(format: " (%.1f MB)", size / (1024 * 1024))
        }
        if exportType == .mp4, downloadedFilePath != nil {
            statusText = tr("Téléchargement terminé\(sizeMsg). Re-encodez pour Final Cut Pro si besoin.",
                            "Download complete\(sizeMsg). Re-encode for Final Cut Pro if needed.")
            showReencode = true
        } else {
            statusText = tr("Téléchargement terminé\(sizeMsg).", "Download complete\(sizeMsg).")
        }
        if let title = meta?.title, !title.isEmpty {
            let entry = HistoryEntry(title: title, url: url.trimmingCharacters(in: .whitespaces),
                                     thumbnailURL: meta?.thumbnailURL,
                                     downloadDate: Self.now())
            history.add(entry)
        }
        if openFolderAfter { revealFolder() }
    }

    func cancelDownload() {
        cancelled = true
        activeProcess?.terminate()
        statusText = tr("Téléchargement arrêté.", "Download stopped.")
    }

    // MARK: - Re-encode for Final Cut Pro

    func reencode() async {
        guard !encoding else {
            cancelReencode = true
            activeProcess?.terminate()
            return
        }
        guard let input = downloadedFilePath, FileManager.default.fileExists(atPath: input),
              let ffmpeg = BinaryLocator.ffmpeg else {
            errorMessage = tr("ffmpeg introuvable ou fichier absent.", "ffmpeg not found or file missing.")
            return
        }
        encoding = true
        cancelReencode = false
        progress = 0
        displayProgress = 0
        startSmoothing()
        statusText = tr("Ré-encodage…", "Re-encoding…")
        let output = input.replacingOccurrences(of: ".mp4", with: "_reencoded.mp4")
        let args = FFmpegService.reencodeArguments(input: input, output: output)
        let duration = meta?.duration ?? 0

        let proc = ManagedProcess()
        activeProcess = proc
        let status = await proc.stream(executable: ffmpeg, arguments: args) { [weak self] line in
            guard let self else { return }
            if duration > 0, let secs = FFmpegService.parseProgressSeconds(line) {
                let pct = min(100, secs / duration * 100)
                self.progress = pct
                self.statusText = String(format: self.tr("Ré-encodage… %.1f %%", "Re-encoding… %.1f%%"), pct)
            }
            if self.cancelReencode { proc.terminate() }
        }
        encoding = false
        activeProcess = nil

        if cancelReencode || status != 0 {
            try? FileManager.default.removeItem(atPath: output)
            statusText = cancelReencode ? tr("Ré-encodage annulé.", "Re-encoding cancelled.")
                                        : tr("Erreur lors du ré-encodage.", "Error during re-encoding.")
        } else {
            try? FileManager.default.removeItem(atPath: input)
            try? FileManager.default.moveItem(atPath: output, toPath: input)
            progress = 100
            statusText = tr("Fichier MP4 ré-encodé et optimisé.", "MP4 re-encoded and optimized.")
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

    private func revealFolder() {
        if let path = downloadedFilePath, FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: outputDirPath))
        }
    }

    // MARK: - Helpers

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
