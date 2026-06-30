import Foundation

enum ExportType: String {
    case mp4, mp3   // .mp3 = "audio export" mode; the specific codec is AudioFormatOut
}

/// Audio output container/codec for audio exports.
enum AudioFormatOut: String, CaseIterable, Identifiable {
    case mp3, m4a, opus, flac, wav
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
    var ext: String { rawValue }
    /// Lossy → the output bitrate applies; FLAC/WAV are lossless.
    var isLossy: Bool { self == .mp3 || self == .m4a || self == .opus }
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
        let filesize: Double?          // exact byte size (server Content-Length), when known
        let filesize_approx: Double?   // yt-dlp's estimate, fallback when no exact size
        let `protocol`: String?        // "https" (DASH/progressive) or "m3u8_native" (HLS)
        let language: String?
        let language_preference: Int?
        let format_note: String?

        /// Best available byte size: exact Content-Length first, else yt-dlp's approximation.
        var knownBytes: Double? { filesize ?? filesize_approx }

        /// HLS streams (YouTube's 91–96) are muxed with a wildly inflated `tbr` and never
        /// carry a filesize. We only fall back to them when no DASH/https format exists.
        var isHLS: Bool { (`protocol` ?? "").hasPrefix("m3u8") }
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

    /// Returns a clean "@handle" (letters/digits/._-, ≤30 chars) or nil. `requireAt`
    /// rejects values without a leading "@" (opaque/numeric uploader IDs from non-YouTube
    /// sites), so the filename suffix stays meaningful or is omitted entirely.
    private static func cleanHandle(_ raw: String?, requireAt: Bool) -> String? {
        guard let r = raw?.trimmingCharacters(in: .whitespaces), !r.isEmpty else { return nil }
        if requireAt && !r.hasPrefix("@") { return nil }
        let body = r.hasPrefix("@") ? String(r.dropFirst()) : r
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard (1...30).contains(body.count), body.allSatisfy({ allowed.contains($0) }) else { return nil }
        return "@" + body
    }

    /// A single playable stream URL (progressive MP4 or HLS) for in-app preview/scrubbing.
    /// Low-res proxy; the real download still uses the chosen high-quality format.
    static func previewURL(url: String, cookiesBrowser: String? = nil) async -> URL? {
        guard let ytDlp = BinaryLocator.ytDlp else { return nil }
        var args = ["-g", "-f", "best[ext=mp4][acodec!=none][vcodec!=none]/18/best", "--no-warnings", "--no-playlist"]
        if let cookiesBrowser { args += ["--cookies-from-browser", cookiesBrowser] }
        args.append(url)
        let res = await Shell.capture(ytDlp, args)
        guard let line = res.stdout.split(separator: "\n").first.map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else { return nil }
        return URL(string: line)
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
    static func analyze(url: String, cookiesBrowser: String? = nil, includeAllFormats: Bool = false) async -> (result: AnalysisResult?, ageRestricted: Bool, infoJSON: String?, error: AnalyzeError?) {
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
        // `channel_handle` is the modern handle (e.g. "@MrBeast"); some extractors surface
        // an "@handle" via `uploader_id`. Anything else (opaque IDs like Dailymotion's
        // "x2klxbt", numeric Twitter IDs) is rejected → no handle suffix in the filename.
        meta.channelHandle = cleanHandle(info.channel_handle, requireAt: false)
            ?? cleanHandle(info.uploader_id, requireAt: true)
        if let raw = info.upload_date, raw.count == 8 {
            let y = raw.prefix(4), m = raw.dropFirst(4).prefix(2), d = raw.dropFirst(6).prefix(2)
            meta.uploadDate = "\(y)-\(m)-\(d)"
        }
        meta.viewCount = info.view_count
        meta.likeCount = info.like_count
        meta.commentCount = info.comment_count
        meta.duration = info.duration
        meta.thumbnailURL = info.thumbnail

        let (videoFormats, audioFormats) = buildFormats(info.formats ?? [], includeAllFormats: includeAllFormats)
        return (AnalysisResult(meta: meta, videoFormats: videoFormats, audioFormats: audioFormats), false, res.stdout, nil)
    }

    private static func buildFormats(_ formats: [RawFormat], includeAllFormats: Bool) -> ([VideoFormat], [AudioFormat]) {
        var audioOnly: [AudioFormat] = []
        // We pick "best audio" for video+audio combos in Auto mode. YouTube increasingly
        // ships AI dubs (often at higher bitrate than the original), so picking purely on
        // ABR ends up grabbing a random language. Prefer formats marked as original
        // (yt-dlp's `language_preference >= 0`, or "original" in the note) and fall back
        // to plain highest-ABR only if nothing original was found.
        var bestAudioMP4Original: (id: String, abr: Int, bytes: Double?)? = nil
        var bestAudioMP4Any: (id: String, abr: Int, bytes: Double?)? = nil
        var bestAudioAnyOriginal: (id: String, abr: Int, bytes: Double?)? = nil
        var bestAudioAnyAny: (id: String, abr: Int, bytes: Double?)? = nil

        // (w, h, fps) -> best (id, tbr, isMP4, bytes). Prefer MP4 over an equal-resolution WebM.
        var muxed: [Key: (id: String, tbr: Int, mp4: Bool, bytes: Double?)] = [:]
        var videoOnly: [Key: (id: String, tbr: Int, mp4: Bool, bytes: Double?)] = [:]
        // HLS muxed streams, kept apart and only used when a resolution has no https format.
        var fallbackHLS: [Key: (id: String, tbr: Int, mp4: Bool, bytes: Double?)] = [:]
        func better(_ newTBR: Int, _ newMP4: Bool, than cur: (id: String, tbr: Int, mp4: Bool, bytes: Double?)?) -> Bool {
            guard let cur else { return true }
            if newMP4 != cur.mp4 { return newMP4 }   // MP4 wins at equal resolution
            return newTBR > cur.tbr
        }

        for f in formats {
            let ext = (f.ext ?? "").lowercased()
            let note = (f.format_note ?? "").lowercased()
            if ext == "mhtml" || note.contains("storyboard") { continue }
            let hasVideo = (f.vcodec ?? "none") != "none"
            let hasAudio = (f.acodec ?? "none") != "none"
            let tbr = Int((f.tbr ?? 0).rounded())
            let bytes = f.knownBytes

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
                        bestAudioMP4Any = (f.format_id, abr, bytes)
                    }
                    if isOriginal, bestAudioMP4Original == nil || abr > bestAudioMP4Original!.abr {
                        bestAudioMP4Original = (f.format_id, abr, bytes)
                    }
                }
                if bestAudioAnyAny == nil || abr > bestAudioAnyAny!.abr {
                    bestAudioAnyAny = (f.format_id, abr, bytes)
                }
                if isOriginal, bestAudioAnyOriginal == nil || abr > bestAudioAnyOriginal!.abr {
                    bestAudioAnyOriginal = (f.format_id, abr, bytes)
                }
            } else if hasVideo {
                let isMP4 = (ext == "mp4")
                guard ext == "mp4" || (includeAllFormats && (ext == "webm" || ext == "mkv")),
                      let w = f.width, let h = f.height else { continue }
                let fps = Int((f.fps ?? 30).rounded())
                let key = Key(w: w, h: h, fps: fps)
                if f.isHLS {
                    // Keep HLS aside; its inflated tbr would otherwise beat every DASH format.
                    if better(tbr, isMP4, than: fallbackHLS[key]) { fallbackHLS[key] = (f.format_id, tbr, isMP4, bytes) }
                } else if hasAudio {
                    if better(tbr, isMP4, than: muxed[key]) { muxed[key] = (f.format_id, tbr, isMP4, bytes) }
                } else {
                    if better(tbr, isMP4, than: videoOnly[key]) { videoOnly[key] = (f.format_id, tbr, isMP4, bytes) }
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
        let keys = Set(muxed.keys).union(videoOnly.keys).union(fallbackHLS.keys)
        for key in keys.sorted(by: { (min($0.w, $0.h), $0.fps) < (min($1.w, $1.h), $1.fps) }) {
            let mux = muxed[key]
            let vid = videoOnly[key]
            var chosenID: String? = mux?.id
            var chosenTBR = mux?.tbr ?? 0
            var chosenMP4 = mux?.mp4 ?? true
            var chosenBytes = mux?.bytes
            if let vid, let audio = bestAudio {
                let comboTBR = vid.tbr + audio.abr
                if comboTBR > chosenTBR {
                    chosenID = "\(vid.id)+\(audio.id)"
                    chosenTBR = comboTBR
                    chosenMP4 = vid.mp4
                    // Sum component sizes only when both are known; otherwise leave nil so
                    // the UI falls back to the bitrate estimate rather than show a half-total.
                    chosenBytes = (vid.bytes != nil && audio.bytes != nil) ? vid.bytes! + audio.bytes! : nil
                }
            }
            // No DASH/https format at this resolution — accept the HLS stream as a last resort.
            if chosenID == nil, let hls = fallbackHLS[key] {
                chosenID = hls.id
                chosenTBR = hls.tbr
                chosenMP4 = hls.mp4
                chosenBytes = hls.bytes
            }
            if let id = chosenID {
                result.append(VideoFormat(id: id, width: key.w, height: key.h, fps: key.fps,
                                          tbr: chosenTBR, container: chosenMP4 ? "mp4" : "mkv",
                                          sizeBytes: chosenBytes))
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
                                  audioFormat: String = "mp3",
                                  mergeContainer: String = "mp4",
                                  outputPath: String,
                                  cookiesBrowser: String?,
                                  infoJSONPath: String? = nil,
                                  downloadSection: String? = nil,
                                  forceKeyframes: Bool = false,
                                  embedMetadata: Bool = false,
                                  sponsorBlock: Bool = false) -> [String] {
        let isAuto = audioLanguage.lowercased() == "auto"
        var args: [String] = []

        if exportType == .mp4 {
            if isAuto {
                args = ["-f", formatID, "--merge-output-format", mergeContainer]
            } else if formatID.contains("+") {
                let vid = formatID.split(separator: "+").first.map(String.init) ?? formatID
                let expr = "\(vid)+ba[language^=\(audioLanguage)]/(bestvideo+bestaudio/b)"
                args = ["-f", expr, "--merge-output-format", mergeContainer, "-S", "lang:\(audioLanguage)"]
            } else {
                args = ["-f", formatID, "--merge-output-format", mergeContainer, "-S", "lang:\(audioLanguage)"]
            }
        } else {
            // MP3: always take the best available audio (optionally for a given language)
            // and let ffmpeg encode to the chosen output bitrate. Which source stream it
            // came from is irrelevant once re-encoded, so we don't expose it.
            let selector = isAuto ? "bestaudio/best" : "ba[language^=\(audioLanguage)]/bestaudio/best"
            args = ["-f", selector, "--extract-audio", "--audio-format", audioFormat]
            if ["mp3", "m4a", "opus"].contains(audioFormat) { args += ["--audio-quality", "\(mp3Bitrate)K"] }
            if !isAuto { args += ["-S", "lang:\(audioLanguage)"] }
        }

        if let downloadSection {
            args += ["--download-sections", downloadSection]
            if forceKeyframes { args += ["--force-keyframes-at-cuts"] }
        }
        if embedMetadata { args += ["--embed-metadata", "--embed-thumbnail", "--embed-chapters"] }
        if sponsorBlock { args += ["--sponsorblock-remove", "default"] }
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
