import Foundation

/// A long-running child process whose output is streamed line-by-line.
/// Splits on both `\n` (yt-dlp --newline) and `\r` (ffmpeg progress).
final class ManagedProcess {
    private let process = Process()
    private let lock = NSLock()
    private var buffer = Data()

    var isRunning: Bool { process.isRunning }

    func stream(executable: String,
                arguments: [String],
                onLine: @escaping @MainActor (String) -> Void) async -> Int32 {
        await withCheckedContinuation { (cont: CheckedContinuation<Int32, Never>) in
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = BinaryLocator.childEnvironment
            process.standardOutput = pipe
            process.standardError = pipe

            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { [weak self] h in
                guard let self else { return }
                let data = h.availableData
                if data.isEmpty { return }
                self.lock.lock()
                self.buffer.append(data)
                var lines: [String] = []
                while let idx = self.buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                    let lineData = self.buffer.subdata(in: self.buffer.startIndex..<idx)
                    self.buffer.removeSubrange(self.buffer.startIndex...idx)
                    if let line = String(data: lineData, encoding: .utf8) {
                        lines.append(line)
                    }
                }
                self.lock.unlock()
                for line in lines {
                    Task { @MainActor in onLine(line) }
                }
            }

            process.terminationHandler = { [weak self] proc in
                handle.readabilityHandler = nil
                if let self {
                    self.lock.lock()
                    let remaining = self.buffer
                    self.buffer.removeAll()
                    self.lock.unlock()
                    if !remaining.isEmpty, let line = String(data: remaining, encoding: .utf8) {
                        Task { @MainActor in onLine(line) }
                    }
                }
                cont.resume(returning: proc.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                handle.readabilityHandler = nil
                cont.resume(returning: -1)
            }
        }
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }
}
