import Foundation

struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String
    var combined: String { stdout + "\n" + stderr }
    var succeeded: Bool { status == 0 }
}

/// Locates command-line tools that are not on a Finder-launched app's PATH.
enum BinaryLocator {
    static let searchDirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

    static func find(_ name: String) -> String? {
        for dir in searchDirs {
            let path = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    static var ytDlp: String? { find("yt-dlp") }
    static var ffmpeg: String? { find("ffmpeg") }
    static var ffprobe: String? { find("ffprobe") }

    /// PATH passed to child processes so yt-dlp can locate ffmpeg/ffprobe.
    static var childPath: String { searchDirs.joined(separator: ":") }
    static var childEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = childPath
        return env
    }
}

/// One-shot command execution capturing full output. Reads both pipes concurrently to avoid deadlocks.
enum Shell {
    static func capture(_ executable: String, _ arguments: [String]) async -> CommandResult {
        await withCheckedContinuation { (cont: CheckedContinuation<CommandResult, Never>) in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.environment = BinaryLocator.childEnvironment
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                } catch {
                    cont.resume(returning: CommandResult(status: -1, stdout: "", stderr: error.localizedDescription))
                    return
                }

                var outData = Data()
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                process.waitUntilExit()
                group.wait()

                cont.resume(returning: CommandResult(
                    status: process.terminationStatus,
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? ""
                ))
            }
        }
    }
}
