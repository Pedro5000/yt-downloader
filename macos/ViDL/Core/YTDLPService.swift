import Foundation

enum ExportType: String {
    case mp4, mp3
}

enum YTDLPService {

    // MARK: - JSON decoding of `yt-dlp -j`

    private struct RawFormat: Decodable {
        let format_id: String
        let ext: String?
        let vcodec: String?
        let acodec: String?
        let width: Int?
        let height: Int?
        let fps: Double?
        let tbr: Double?
        let abr: Double?
        let language: String?
        let format_note: String?
    }

    private struct RawInfo: Decodable {
        let title: String?
        let uploader: String?
        let upload_date: String?
        let view_count: Int?
        let like_count: Int?
        let comment_count: Int?
        let duration: Double?
        let thumbnail: String?
        let formats: [RawFormat]?
    }

    static func needsAgeRetry(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("sign in to confirm") || lower.contains("age-restricted")
    }

    /// Runs a single `yt-dlp -j` call and builds the format lists from the JSON `formats` array.
    static func analyze(url: String, useCookies: Bool = false) async -> (result: AnalysisResult?, ageRestricted: Bool) {
        guard let ytDlp = BinaryLocator.ytDlp else { return (nil, false) }
        var args = ["-j", "--no-warnings", "--no-playlist"]
        if useCookies { args += ["--cookies-from-browser", "firefox"] }
        args.append(url)

        let res = await Shell.capture(ytDlp, args)
        if !res.succeeded {
            return (nil, needsAgeRetry(res.combined))
        }
        guard let data = res.stdout.data(using: .utf8),
              let info = try? JSONDecoder().decode(RawInfo.self, from: data) else {
            return (nil, false)
        }

        var meta = VideoMeta()
        meta.title = info.title
        meta.uploader = info.uploader
        if let raw = info.upload_date, raw.count == 8 {
            let y = raw.prefix(4), m = raw.dropFirst(4).prefix(2), d = raw.dropFirst(6).prefix(2)
            meta.uploadDate = "\(y)-\(m)-\(d)"
        }
        meta.viewCount = info.view_count
        meta.likeCount = info.like_count
        meta.commentCount = info.comment_count
        meta.duration = info.duration
        meta.thumbnailURL = info.thumbnail

        let (videoFormats, audioFormats) = buildFormats(info.formats ?? [])
        return (AnalysisResult(meta: meta, videoFormats: videoFormats, audioFormats: audioFormats), false)
    }

    private static func buildFormats(_ formats: [RawFormat]) -> ([VideoFormat], [AudioFormat]) {
        var audioOnly: [AudioFormat] = []
        var bestAudioMP4: (id: String, abr: Int)? = nil
        var bestAudioAny: (id: String, abr: Int)? = nil

        // (w, h, fps) -> best tbr
        var muxed: [Key: (id: String, tbr: Int)] = [:]
        var videoOnly: [Key: (id: String, tbr: Int)] = [:]

        for f in formats {
            let ext = (f.ext ?? "").lowercased()
            let note = (f.format_note ?? "").lowercased()
            if ext == "mhtml" || note.contains("storyboard") { continue }
            let hasVideo = (f.vcodec ?? "none") != "none"
            let hasAudio = (f.acodec ?? "none") != "none"
            let tbr = Int((f.tbr ?? 0).rounded())

            if !hasVideo && hasAudio {
                let abr = Int((f.abr ?? f.tbr ?? 0).rounded())
                var label = "\(f.format_id) | \(ext) audio"
                if abr > 0 { label += " \(abr)k" }
                if let lang = f.language, !lang.isEmpty { label += " [\(lang)]" }
                audioOnly.append(AudioFormat(id: f.format_id, label: label))
                if ext == "m4a" || ext == "mp4" {
                    if bestAudioMP4 == nil || abr > bestAudioMP4!.abr { bestAudioMP4 = (f.format_id, abr) }
                }
                if bestAudioAny == nil || abr > bestAudioAny!.abr { bestAudioAny = (f.format_id, abr) }
            } else if hasVideo {
                guard ext == "mp4", let w = f.width, let h = f.height else { continue }
                let fps = Int((f.fps ?? 30).rounded())
                let key = Key(w: w, h: h, fps: fps)
                if hasAudio {
                    if let cur = muxed[key], cur.tbr >= tbr { } else { muxed[key] = (f.format_id, tbr) }
                } else {
                    if let cur = videoOnly[key], cur.tbr >= tbr { } else { videoOnly[key] = (f.format_id, tbr) }
                }
            }
        }

        let bestAudio = bestAudioMP4 ?? bestAudioAny

        var result: [VideoFormat] = []
        let keys = Set(muxed.keys).union(videoOnly.keys)
        for key in keys.sorted(by: { (min($0.w, $0.h), $0.fps) < (min($1.w, $1.h), $1.fps) }) {
            let mux = muxed[key]
            let vid = videoOnly[key]
            var chosenID: String? = mux?.id
            var chosenTBR = mux?.tbr ?? 0
            if let vid, let audio = bestAudio {
                let comboTBR = vid.tbr + audio.abr
                if comboTBR > chosenTBR {
                    chosenID = "\(vid.id)+\(audio.id)"
                    chosenTBR = comboTBR
                }
            }
            if let id = chosenID {
                result.append(VideoFormat(id: id, width: key.w, height: key.h, fps: key.fps, tbr: chosenTBR))
            }
        }
        return (result, audioOnly)
    }

    private struct Key: Hashable {
        let w: Int; let h: Int; let fps: Int
    }

    // MARK: - Download command building

    static func downloadArguments(url: String,
                                  formatID: String,
                                  exportType: ExportType,
                                  audioLanguage: String,
                                  outputPath: String,
                                  useCookies: Bool) -> [String] {
        let isAuto = audioLanguage.lowercased() == "auto"
        var args: [String] = []

        if exportType == .mp4 {
            if isAuto {
                args = ["-f", formatID, "--merge-output-format", "mp4"]
            } else if formatID.contains("+") {
                let vid = formatID.split(separator: "+").first.map(String.init) ?? formatID
                let expr = "\(vid)+ba[language^=\(audioLanguage)]/(bestvideo+bestaudio/b)"
                args = ["-f", expr, "--merge-output-format", "mp4", "-S", "lang:\(audioLanguage)"]
            } else {
                args = ["-f", formatID, "--merge-output-format", "mp4", "-S", "lang:\(audioLanguage)"]
            }
        } else {
            if isAuto {
                args = ["-f", formatID, "--extract-audio", "--audio-format", "mp3"]
            } else {
                let expr = "ba[language^=\(audioLanguage)]/bestaudio"
                args = ["-f", expr, "--extract-audio", "--audio-format", "mp3", "-S", "lang:\(audioLanguage)"]
            }
        }

        args += ["--no-playlist", "--newline", "-o", outputPath]
        if useCookies { args += ["--cookies-from-browser", "firefox"] }
        args.append(url)
        return args
    }
}
