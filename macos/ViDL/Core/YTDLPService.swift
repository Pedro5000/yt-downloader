import Foundation

enum ExportType: String {
    case mp4, mp3
}

/// Classified reason an analysis failed, mapped to a localized message by the view model.
enum AnalyzeError: Equatable {
    case ageRestricted, privateVideo, membersOnly, unavailable, geoBlocked
    case notFound, network, unsupportedURL, notYetAvailable, signInRequired
    case other(String)   // raw cleaned yt-dlp message
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
        let language_preference: Int?
        let format_note: String?
    }

    private struct RawInfo: Decodable {
        let title: String?
        let uploader: String?
        let channel_handle: String?
        let uploader_id: String?
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

    /// Maps yt-dlp's combined output to a friendly, classified reason.
    static func classify(_ combined: String) -> AnalyzeError {
        let l = combined.lowercased()
        func has(_ s: String) -> Bool { l.contains(s) }
        if has("age-restricted") || has("confirm your age") { return .ageRestricted }
        if has("private video") { return .privateVideo }
        if has("members-only") || has("join this channel") { return .membersOnly }
        if has("not available in your country") || has("blocked it in your country") || has("geo restrict") { return .geoBlocked }
        if has("video unavailable") || has("this video is unavailable") || has("has been removed") || has("no longer available") { return .unavailable }
        if has("http error 404") || has("404: not found") { return .notFound }
        if has("unable to download webpage") || has("failed to resolve") || has("getaddrinfo")
            || has("temporary failure in name resolution") || has("timed out") || has("network is unreachable")
            || has("connection refused") || has("connection reset") { return .network }
        if has("unsupported url") { return .unsupportedURL }
        if has("premieres in") || has("live event will begin") || has("this live event") { return .notYetAvailable }
        if has("sign in") || has("login required") || has("cookies") { return .signInRequired }
        // Fall back to the last cleaned ERROR line.
        if let line = combined.split(separator: "\n").last(where: { $0.contains("ERROR:") }) {
            var msg = String(line)
            if let r = msg.range(of: "ERROR:") { msg = String(msg[r.upperBound...]) }
            if let r = msg.range(of: #"^\s*\[[^\]]+\]\s*[^:]*:\s*"#, options: .regularExpression) { msg.removeSubrange(r) }
            msg = msg.trimmingCharacters(in: .whitespacesAndNewlines)
            if !msg.isEmpty { return .other(msg) }
        }
        return .other("")
    }

    /// Runs a single `yt-dlp -j` call and builds the format lists from the JSON `formats` array.
    static func analyze(url: String, cookiesBrowser: String? = nil) async -> (result: AnalysisResult?, ageRestricted: Bool, infoJSON: String?, error: AnalyzeError?) {
        guard let ytDlp = BinaryLocator.ytDlp else { return (nil, false, nil, .other("")) }
        var args = ["-j", "--no-warnings", "--no-playlist"]
        if let cookiesBrowser { args += ["--cookies-from-browser", cookiesBrowser] }
        args.append(url)

        let res = await Shell.capture(ytDlp, args)
        if !res.succeeded {
            return (nil, needsAgeRetry(res.combined), nil, classify(res.combined))
        }
        guard let data = res.stdout.data(using: .utf8),
              let info = try? JSONDecoder().decode(RawInfo.self, from: data) else {
            return (nil, false, nil, .other(""))
        }

        var meta = VideoMeta()
        meta.title = info.title
        meta.uploader = info.uploader
        // `channel_handle` is the modern field (e.g. "@MrBeast"); older extractors
        // surface the same handle via `uploader_id` when it starts with "@".
        if let h = info.channel_handle, !h.isEmpty {
            meta.channelHandle = h
        } else if let h = info.uploader_id, h.hasPrefix("@") {
            meta.channelHandle = h
        }
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
        return (AnalysisResult(meta: meta, videoFormats: videoFormats, audioFormats: audioFormats), false, res.stdout, nil)
    }

    private static func buildFormats(_ formats: [RawFormat]) -> ([VideoFormat], [AudioFormat]) {
        var audioOnly: [AudioFormat] = []
        // We pick "best audio" for video+audio combos in Auto mode. YouTube increasingly
        // ships AI dubs (often at higher bitrate than the original), so picking purely on
        // ABR ends up grabbing a random language. Prefer formats marked as original
        // (yt-dlp's `language_preference >= 0`, or "original" in the note) and fall back
        // to plain highest-ABR only if nothing original was found.
        var bestAudioMP4Original: (id: String, abr: Int)? = nil
        var bestAudioMP4Any: (id: String, abr: Int)? = nil
        var bestAudioAnyOriginal: (id: String, abr: Int)? = nil
        var bestAudioAnyAny: (id: String, abr: Int)? = nil

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
                let isOriginal = (f.language_preference ?? -1) >= 0 || note.contains("original")
                var label = "\(f.format_id) | \(ext) audio"
                if abr > 0 { label += " \(abr)k" }
                if let lang = f.language, !lang.isEmpty {
                    label += isOriginal ? " [\(lang) original]" : " [\(lang)]"
                }
                audioOnly.append(AudioFormat(id: f.format_id, label: label))
                let isMP4 = (ext == "m4a" || ext == "mp4")
                if isMP4 {
                    if bestAudioMP4Any == nil || abr > bestAudioMP4Any!.abr {
                        bestAudioMP4Any = (f.format_id, abr)
                    }
                    if isOriginal, bestAudioMP4Original == nil || abr > bestAudioMP4Original!.abr {
                        bestAudioMP4Original = (f.format_id, abr)
                    }
                }
                if bestAudioAnyAny == nil || abr > bestAudioAnyAny!.abr {
                    bestAudioAnyAny = (f.format_id, abr)
                }
                if isOriginal, bestAudioAnyOriginal == nil || abr > bestAudioAnyOriginal!.abr {
                    bestAudioAnyOriginal = (f.format_id, abr)
                }
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

        // Prefer original-language audio in MP4 (cleanest mux), then any original,
        // then highest-ABR MP4, then highest-ABR overall.
        let bestAudio = bestAudioMP4Original
            ?? bestAudioAnyOriginal
            ?? bestAudioMP4Any
            ?? bestAudioAnyAny

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
                                  mp3Bitrate: String,
                                  outputPath: String,
                                  cookiesBrowser: String?,
                                  infoJSONPath: String? = nil) -> [String] {
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
            // MP3: always take the best available audio (optionally for a given language)
            // and let ffmpeg encode to the chosen output bitrate. Which source stream it
            // came from is irrelevant once re-encoded, so we don't expose it.
            let selector = isAuto ? "bestaudio/best" : "ba[language^=\(audioLanguage)]/bestaudio/best"
            args = ["-f", selector, "--extract-audio", "--audio-format", "mp3", "--audio-quality", "\(mp3Bitrate)K"]
            if !isAuto { args += ["-S", "lang:\(audioLanguage)"] }
        }

        args += ["--no-playlist", "--newline", "-o", outputPath]
        if let cookiesBrowser { args += ["--cookies-from-browser", cookiesBrowser] }
        if let infoJSONPath {
            // Reuse the info extracted during analysis — skips the webpage/player/challenge
            // round-trip, so the download starts almost immediately.
            args += ["--load-info-json", infoJSONPath]
        } else {
            args.append(url)
        }
        return args
    }
}
