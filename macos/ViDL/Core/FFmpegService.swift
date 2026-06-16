import Foundation
import AppKit

struct ConversionSettings {
    var outputFormat: String = "mp4"
    var quality: String = "Standard"          // Low / Standard / High / Very High
    var resolution: String = "Original"       // Original / 144p ... 2160p
    var sampleRate: String = "44100"
    var optimizeStreaming: Bool = false
    // Advanced
    var videoEncoder: String = "libx264"
    var videoBitrate: String = "1000k"
    var videoFramerate: String = "Original"
    var videoPreset: String = "medium"
    var audioEncoder: String = "aac"
    var audioChannels: String = "Stereo"
    var audioBitrate: String = "128k"
}

enum FFmpegService {

    // MARK: - ffprobe

    private struct ProbeStream: Decodable {
        let codec_type: String?
        let codec_name: String?
        let width: Int?
        let height: Int?
        let sample_rate: String?
        let channels: Int?
        let avg_frame_rate: String?
    }
    private struct ProbeFormat: Decodable {
        let duration: String?
        let format_name: String?
        let bit_rate: String?
    }
    private struct ProbeResult: Decodable {
        let streams: [ProbeStream]?
        let format: ProbeFormat?
    }

    static func probe(_ path: String) async -> MediaFileInfo? {
        guard let ffprobe = BinaryLocator.ffprobe else { return nil }
        let args = ["-v", "error", "-show_entries", "format=duration,format_name,bit_rate",
                    "-show_streams", "-of", "json", path]
        let res = await Shell.capture(ffprobe, args)
        guard res.succeeded, let data = res.stdout.data(using: .utf8),
              let probe = try? JSONDecoder().decode(ProbeResult.self, from: data) else { return nil }

        let video = probe.streams?.first { $0.codec_type == "video" }
        let audio = probe.streams?.first { $0.codec_type == "audio" }

        var frameRate = "N/A"
        if let fr = video?.avg_frame_rate, fr.contains("/") {
            let parts = fr.split(separator: "/")
            if parts.count == 2, let n = Double(parts[0]), let d = Double(parts[1]), d != 0 {
                frameRate = String(format: "%.2f", n / d)
            }
        }
        let resolution: String
        if let w = video?.width, let h = video?.height { resolution = "\(w)x\(h)" } else { resolution = "N/A" }

        return MediaFileInfo(
            fileName: (path as NSString).lastPathComponent,
            duration: Double(probe.format?.duration ?? "") ?? 0,
            formatName: probe.format?.format_name ?? "N/A",
            formatBitRate: probe.format?.bit_rate ?? "N/A",
            videoResolution: resolution,
            videoCodec: video?.codec_name ?? "N/A",
            videoFrameRate: frameRate,
            audioCodec: audio?.codec_name ?? "N/A",
            audioSampleRate: audio?.sample_rate ?? "N/A",
            audioChannels: audio?.channels.map(String.init) ?? "N/A"
        )
    }

    static func duration(_ path: String) async -> Double? {
        guard let ffprobe = BinaryLocator.ffprobe else { return nil }
        let args = ["-v", "error", "-show_entries", "format=duration",
                    "-of", "default=noprint_wrappers=1:nokey=1", path]
        let res = await Shell.capture(ffprobe, args)
        return Double(res.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func extractThumbnail(_ path: String) async -> NSImage? {
        guard let ffmpeg = BinaryLocator.ffmpeg else { return nil }
        let tmp = NSTemporaryDirectory() + UUID().uuidString + ".jpg"
        let args = ["-y", "-i", path, "-ss", "00:00:01.000", "-vframes", "1", tmp]
        let res = await Shell.capture(ffmpeg, args)
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        guard res.succeeded, FileManager.default.fileExists(atPath: tmp) else { return nil }
        return NSImage(contentsOfFile: tmp)
    }

    // MARK: - Command building

    static func conversionArguments(input: String, output: String, settings s: ConversionSettings) -> [String] {
        var args = ["-i", input]
        let fmt = s.outputFormat.lowercased()
        let videoFormats: Set<String> = ["mp4", "mkv", "avi", "mov", "flv", "wmv"]
        let audioFormats: Set<String> = ["mp3", "ogg", "wav"]

        if videoFormats.contains(fmt) {
            args += ["-c:v", s.videoEncoder]
            if s.resolution != "Original" {
                let h = s.resolution.replacingOccurrences(of: "p", with: "")
                args += ["-vf", "scale=-2:\(h)"]
            }
            let qmap = ["Low": "28", "Standard": "23", "High": "18", "Very High": "15"]
            args += ["-crf", qmap[s.quality] ?? "23"]
            args += ["-preset", s.videoPreset]
            if s.videoFramerate != "Original" { args += ["-r", s.videoFramerate] }
            args += ["-c:a", s.audioEncoder]
            if s.audioChannels == "Mono" { args += ["-ac", "1"] }
            else if s.audioChannels == "Stereo" { args += ["-ac", "2"] }
            args += ["-b:a", s.audioBitrate]
            if s.sampleRate != "44100" { args += ["-ar", s.sampleRate] }
            if s.optimizeStreaming && fmt == "mp4" { args += ["-movflags", "faststart"] }
        } else if audioFormats.contains(fmt) {
            args.append("-vn")
            let codecMap = ["mp3": "libmp3lame", "ogg": "libvorbis", "wav": "pcm_s16le"]
            args += ["-c:a", codecMap[fmt] ?? s.audioEncoder]
            if s.audioChannels == "Mono" { args += ["-ac", "1"] }
            else if s.audioChannels == "Stereo" { args += ["-ac", "2"] }
            if fmt != "wav" { args += ["-b:a", s.audioBitrate] }
            if s.sampleRate != "44100" { args += ["-ar", s.sampleRate] }
        }
        args.append(output)
        return args
    }

    static func reencodeArguments(input: String, output: String) -> [String] {
        ["-i", input,
         "-c:v", "libx264", "-preset", "slow", "-crf", "18",
         "-c:a", "copy", "-movflags", "faststart",
         output]
    }

    // MARK: - Progress parsing

    /// Parses ffmpeg `time=HH:MM:SS.xx` into seconds.
    static func parseProgressSeconds(_ line: String) -> Double? {
        guard let range = line.range(of: #"time=(\d+):(\d+):(\d+\.\d+)"#, options: .regularExpression) else { return nil }
        let match = String(line[range]).replacingOccurrences(of: "time=", with: "")
        let parts = match.split(separator: ":")
        guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }

    static func parseSizeMB(_ line: String) -> Double? {
        guard let range = line.range(of: #"size=\s*([\d\.]+)(\w+)"#, options: .regularExpression) else { return nil }
        let token = String(line[range]).replacingOccurrences(of: "size=", with: "").trimmingCharacters(in: .whitespaces)
        let valueStr = token.prefix { $0.isNumber || $0 == "." }
        let unit = token.dropFirst(valueStr.count).lowercased()
        guard let value = Double(valueStr) else { return nil }
        if unit.hasPrefix("k") { return value / 1024 }
        if unit.hasPrefix("m") { return value }
        if unit.hasPrefix("g") { return value * 1024 }
        return value / (1024 * 1024)
    }
}
