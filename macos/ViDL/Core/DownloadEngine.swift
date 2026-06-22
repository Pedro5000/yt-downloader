import Foundation
import AppKit

/// Everything needed to download ONE media, frozen at enqueue time. Decouples the
/// engine from mutable UI state (current URL, pickers…) so the same engine drives
/// both the Download tab and the queue.
struct DownloadSpec: Equatable {
    let url: String
    let title: String?
    let channelHandle: String?
    let thumbnailURL: String?
    let exportType: ExportType
    let audioFormat: AudioFormatOut   // codec when exportType == .mp3 (audio mode)
    let formatID: String          // "137+140", or "" for audio
    let mergeContainer: String    // "mp4" | "mkv"
    let audioLanguage: String
    let mp3Bitrate: String
    let outputDirPath: String
    let clipSection: String?      // "*00:10-00:30" or nil
    let forceKeyframes: Bool
    let infoJSONPath: String?     // fast-path: reuse analysis JSON for this URL
    let cookiesBrowser: String?   // yt-dlp value, or nil to disable the cookie retry
    var embedMetadata: Bool = false
    var sponsorBlock: Bool = false
}

struct DownloadOutcome {
    let phase: TransferPhase        // .completed | .failed | .cancelled
    let historyEntry: HistoryEntry? // non-nil on success with a title
}

/// Drives a single download from a `DownloadSpec`, publishing every `TransferPhase`
/// transition via `onPhase`. Touches no UI state — the caller (DownloadViewModel or
/// DownloadQueue) maps the phase onto its own observed property and smoothing.
@MainActor
final class DownloadEngine {
    private var process: ManagedProcess?
    private var cancelled = false
    private var ageDetected = false
    private var lastErrorLine: String?
    private var phase: TransferPhase = .queued
    private var onPhase: (@MainActor (TransferPhase) -> Void)?

    private func setPhase(_ p: TransferPhase) { phase = p; onPhase?(p) }

    /// Terminates the running process; the in-flight `run` resolves to `.cancelled`.
    func cancel() {
        cancelled = true
        process?.terminate()
    }

    func run(spec: DownloadSpec, onPhase: @escaping @MainActor (TransferPhase) -> Void) async -> DownloadOutcome {
        self.onPhase = onPhase
        guard let ytDlp = BinaryLocator.ytDlp else {
            let p = TransferPhase.failed("yt-dlp")
            setPhase(p)
            return DownloadOutcome(phase: p, historyEntry: nil)
        }

        let raw = Formatting.sanitizeFilename(spec.title ?? "video")
        // Bound the title so "<title>_vidl_@handle.ext (n)" stays under the APFS 255-byte limit.
        let stem = Formatting.clampBytes(raw.isEmpty ? "video" : raw, 150)
        let handle = Formatting.sanitizeFilename(spec.channelHandle ?? "")
        let base = handle.isEmpty ? stem + "_vidl" : stem + "_vidl_" + handle
        let ext = spec.exportType == .mp4 ? spec.mergeContainer : spec.audioFormat.ext
        let outputPath = uniquePath(dir: spec.outputDirPath, base: base, ext: ext)
        let snapshot = DownloadSnapshot(title: spec.title, url: spec.url,
                                        thumbnailURL: spec.thumbnailURL, exportType: spec.exportType)
        let expected = spec.formatID.contains("+") ? 2 : 1

        cancelled = false
        ageDetected = false
        lastErrorLine = nil

        func beginPreparing(_ prep: PrepPhase) {
            var t = Transfer(snapshot: snapshot, outputPath: outputPath)
            t.segments.expected = expected
            setPhase(.preparing(prep, t))
        }
        func buildArgs(cookiesBrowser: String?, infoJSONPath: String?) -> [String] {
            YTDLPService.downloadArguments(url: spec.url, formatID: spec.formatID,
                                           exportType: spec.exportType, audioLanguage: spec.audioLanguage,
                                           mp3Bitrate: spec.mp3Bitrate, audioFormat: spec.audioFormat.rawValue,
                                           mergeContainer: spec.mergeContainer,
                                           outputPath: outputPath,
                                           cookiesBrowser: cookiesBrowser, infoJSONPath: infoJSONPath,
                                           downloadSection: spec.clipSection, forceKeyframes: spec.forceKeyframes,
                                           embedMetadata: spec.embedMetadata, sponsorBlock: spec.sponsorBlock)
        }

        beginPreparing(.starting)
        var status: Int32 = -1

        // Fast path: reuse the analysis JSON to skip re-extraction.
        if let infoPath = spec.infoJSONPath, FileManager.default.fileExists(atPath: infoPath) {
            status = await stream(ytDlp, buildArgs(cookiesBrowser: nil, infoJSONPath: infoPath))
            if status != 0 && !cancelled {
                ageDetected = false
                beginPreparing(.starting)
            }
        }
        // Normal extraction (also the fallback when the cached info failed).
        if status != 0 && !cancelled {
            status = await stream(ytDlp, buildArgs(cookiesBrowser: nil, infoJSONPath: nil))
        }
        // Age-restricted retry with the configured browser's cookies.
        if status != 0 && ageDetected && !cancelled, let browser = spec.cookiesBrowser {
            ageDetected = false
            beginPreparing(.cookies)
            status = await stream(ytDlp, buildArgs(cookiesBrowser: browser, infoJSONPath: nil))
        }

        process = nil

        if status == 0 {
            let filePath = phase.transfer?.filePath
            var sizeMB: Double?
            if let path = filePath,
               let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Double {
                sizeMB = size / (1024 * 1024)
            }
            setPhase(.completed(Completion(snapshot: snapshot, filePath: filePath, sizeMB: sizeMB)))
            var entry: HistoryEntry?
            if let title = spec.title, !title.isEmpty {
                entry = HistoryEntry(title: title, url: spec.url, thumbnailURL: spec.thumbnailURL,
                                     downloadDate: Self.now(), filePath: filePath)
            }
            return DownloadOutcome(phase: phase, historyEntry: entry)
        } else if cancelled {
            cleanupIncompleteFiles(outputPath: outputPath)
            setPhase(.cancelled)
            return DownloadOutcome(phase: .cancelled, historyEntry: nil)
        } else {
            setPhase(.failed(cleanedError() ?? "Download failed."))
            return DownloadOutcome(phase: phase, historyEntry: nil)
        }
    }

    // MARK: - Process streaming + line parsing

    private func stream(_ executable: String, _ args: [String]) async -> Int32 {
        let proc = ManagedProcess()
        process = proc
        return await proc.stream(executable: executable, arguments: args) { [weak self] line in
            self?.handleLine(line)
        }
    }

    private func withTransfer(_ body: (inout Transfer) -> Void) {
        switch phase {
        case .preparing(let p, var t): body(&t); setPhase(.preparing(p, t))
        case .downloading(var t):      body(&t); setPhase(.downloading(t))
        case .finalizing(let k, var t): body(&t); setPhase(.finalizing(k, t))
        default: break
        }
    }

    private func handleLine(_ line: String) {
        if line.contains("Sign in to confirm") || line.lowercased().contains("age-restricted") {
            ageDetected = true
        }
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
            if let t = phase.transfer { setPhase(.finalizing(.merging, t)) }
        } else if line.hasPrefix("[ExtractAudio]") {
            if let t = phase.transfer { setPhase(.finalizing(.extracting, t)) }
        } else if case .preparing(let prep, let t) = phase {
            let lower = line.lowercased()
            var next: PrepPhase?
            if lower.contains("solving") || lower.contains("challenge") {
                next = .verifying
            } else if lower.contains("m3u8") || lower.contains("manifest") || lower.contains("fragments") {
                next = .preparingStream
            } else if line.hasPrefix("[youtube]") || line.hasPrefix("[info]") {
                next = .fetchingInfo
            }
            if let next, next > prep { setPhase(.preparing(next, t)) }
        }

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
            if case .preparing(_, let t) = phase, t.progress > 0 {
                setPhase(.downloading(t))
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

    /// Removes the partial output and yt-dlp's intermediate per-stream files left behind
    /// on cancel. Safe because the `_vidl` suffix + uniquePath make the stem unique.
    private func cleanupIncompleteFiles(outputPath: String) {
        let fm = FileManager.default
        let dir = (outputPath as NSString).deletingLastPathComponent
        let stem = ((outputPath as NSString).deletingPathExtension as NSString).lastPathComponent
        guard !stem.isEmpty, let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
        for name in names where name == stem || name.hasPrefix(stem + ".") {
            try? fm.removeItem(atPath: "\(dir)/\(name)")
        }
    }

    private func cleanedError() -> String? {
        guard var msg = lastErrorLine else { return nil }
        if let range = msg.range(of: #"^\[[^\]]+\]\s*[^:]*:\s*"#, options: .regularExpression) {
            msg.removeSubrange(range)
        }
        msg = msg.trimmingCharacters(in: .whitespacesAndNewlines)
        return msg.isEmpty ? nil : msg
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
