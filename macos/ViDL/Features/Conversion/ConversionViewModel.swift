import SwiftUI
import AppKit
import Observation

@Observable
@MainActor
final class ConversionViewModel {
    var filePath: String?
    var fileInfo: MediaFileInfo?
    var thumbnail: NSImage?

    var settings = ConversionSettings()
    var showAdvanced = false

    var converting = false
    var progress: Double = 0
    var statusText = ""
    var estimatedSize = "N/A"

    var errorMessage: String?

    var app: AppState?
    private func tr(_ fr: String, _ en: String) -> String { app?.tr(fr, en) ?? fr }

    private var outputFile: String?
    private var duration: Double = 0
    private var activeProcess: ManagedProcess?
    private var cancelled = false

    static let outputFormats = ["mp4", "mp3", "mkv", "avi", "mov", "flv", "wmv", "ogg", "wav"]
    static let qualities = ["Low", "Standard", "High", "Very High"]
    static let resolutions = ["Original", "144p", "240p", "360p", "480p", "720p", "1080p", "1440p", "2160p"]
    static let sampleRates = ["8000", "11025", "16000", "22050", "32000", "44100", "48000", "88200", "96000"]
    static let videoEncoders = ["libx264", "libx265", "mpeg4", "libvpx-vp9", "libaom-av1"]
    static let videoBitrates = ["500k", "1000k", "2000k", "3000k"]
    static let videoFramerates = ["Original", "24", "30", "60"]
    static let videoPresets = ["ultrafast", "superfast", "veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow"]
    static let audioEncoders = ["aac", "mp3", "ac3", "opus", "flac", "pcm_s16le"]
    static let audioChannelsOptions = ["Mono", "Stereo"]
    static let audioBitrates = ["64k", "128k", "192k", "256k", "320k"]

    func chooseFile() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await loadFile(path: url.path)
    }

    var hasMissingFFmpeg: Bool { BinaryLocator.ffmpeg == nil }

    func loadFile(path: String) async {
        filePath = path
        settings = ConversionSettings()
        fileInfo = await FFmpegService.probe(path)
        thumbnail = await FFmpegService.extractThumbnail(path)
    }

    func playFile() {
        guard let filePath, FileManager.default.fileExists(atPath: filePath) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: filePath))
    }

    func startConversion() async {
        guard let input = filePath, FileManager.default.fileExists(atPath: input) else {
            errorMessage = tr("Veuillez choisir un fichier valide.", "Please choose a valid file.")
            return
        }
        guard let ffmpeg = BinaryLocator.ffmpeg else {
            errorMessage = tr("ffmpeg introuvable.", "ffmpeg not found.")
            return
        }
        guard let dur = await FFmpegService.duration(input) else {
            errorMessage = tr("Impossible d'obtenir la durée du fichier.", "Unable to get file duration.")
            return
        }
        duration = dur

        let base = (input as NSString).deletingPathExtension
        let fmt = settings.outputFormat
        var output = "\(base)_converted.\(fmt)"
        var i = 1
        while FileManager.default.fileExists(atPath: output) {
            output = "\(base)_converted(\(i)).\(fmt)"
            i += 1
        }
        outputFile = output

        progress = 0
        estimatedSize = "N/A"
        statusText = tr("Conversion en cours…", "Converting…")
        converting = true
        cancelled = false

        let args = FFmpegService.conversionArguments(input: input, output: output, settings: settings)
        let proc = ManagedProcess()
        activeProcess = proc
        let status = await proc.stream(executable: ffmpeg, arguments: args) { [weak self] line in
            guard let self else { return }
            if self.duration > 0, let secs = FFmpegService.parseProgressSeconds(line) {
                let pct = min(100, secs / self.duration * 100)
                self.progress = pct
                self.statusText = String(format: self.tr("Conversion… %.1f %%", "Converting… %.1f%%"), pct)
            }
            if let mb = FFmpegService.parseSizeMB(line) {
                self.estimatedSize = String(format: "~%.1f MB", mb)
            }
            if self.cancelled { proc.terminate() }
        }
        converting = false
        activeProcess = nil

        if cancelled {
            try? FileManager.default.removeItem(atPath: output)
            statusText = tr("Conversion annulée.", "Conversion cancelled.")
        } else if status == 0 {
            progress = 100
            statusText = tr("Conversion terminée.", "Conversion complete.")
            if let attrs = try? FileManager.default.attributesOfItem(atPath: output),
               let size = attrs[.size] as? Double {
                estimatedSize = String(format: "%.1f MB", size / (1024 * 1024))
            }
        } else {
            statusText = tr("La conversion a échoué.", "Conversion failed.")
        }
    }

    func cancelConversion() {
        cancelled = true
        activeProcess?.terminate()
        statusText = tr("Annulation en cours…", "Cancelling…")
    }
}
