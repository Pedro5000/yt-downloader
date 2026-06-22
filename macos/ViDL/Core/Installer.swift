import Foundation
import Observation

/// Runs `brew install <packages>` in-app and streams progress, so a fresh machine
/// can get yt-dlp/ffmpeg without touching the Terminal.
@Observable
@MainActor
final class Installer {
    var running = false
    var lastLine = ""
    var lastResult: Bool?
    private var proc: ManagedProcess?

    func install(_ packages: [String], brew: String) async {
        guard !running else { return }
        running = true
        lastResult = nil
        lastLine = ""
        let p = ManagedProcess()
        proc = p
        let status = await p.stream(executable: brew, arguments: ["install"] + packages) { [weak self] line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { self?.lastLine = trimmed }
        }
        running = false
        proc = nil
        lastResult = (status == 0)
    }
}
