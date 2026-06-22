import Foundation

struct VideoMeta {
    var title: String?
    var uploader: String?
    var channelHandle: String?
    var uploadDate: String?
    var viewCount: Int?
    var likeCount: Int?
    var commentCount: Int?
    var duration: Double?
    var thumbnailURL: String?
}

struct VideoFormat: Identifiable, Hashable {
    let id: String          // yt-dlp format selector, e.g. "137+140"
    let width: Int
    let height: Int
    let fps: Int
    let tbr: Int            // total bitrate, kbps
}

struct AudioFormat: Identifiable, Hashable {
    let id: String
    let label: String
}

struct AnalysisResult {
    var meta: VideoMeta
    var videoFormats: [VideoFormat]
    var audioFormats: [AudioFormat]
}

struct MediaFileInfo {
    var fileName: String
    var duration: Double
    var formatName: String
    var formatBitRate: String
    var videoResolution: String
    var videoCodec: String
    var videoFrameRate: String
    var audioCodec: String
    var audioSampleRate: String
    var audioChannels: String
}

struct HistoryEntry: Identifiable, Hashable, Codable {
    var id: UUID
    var title: String
    var url: String
    var thumbnailURL: String?
    var downloadDate: String
    /// Absolute path of the downloaded file, when known. Optional so old entries and
    /// the shared Python history.json (which never wrote it) decode fine.
    var filePath: String?

    init(title: String, url: String, thumbnailURL: String?, downloadDate: String, filePath: String? = nil) {
        self.id = UUID()
        self.title = title
        self.url = url
        self.thumbnailURL = thumbnailURL
        self.downloadDate = downloadDate
        self.filePath = filePath
    }

    // Compatible with the existing Python history.json (snake_case, no id field).
    enum CodingKeys: String, CodingKey {
        case title, url
        case thumbnailURL = "thumbnail_url"
        case downloadDate = "download_date"
        case filePath = "file_path"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.title = (try? c.decode(String.self, forKey: .title)) ?? ""
        self.url = (try? c.decode(String.self, forKey: .url)) ?? ""
        self.thumbnailURL = try? c.decodeIfPresent(String.self, forKey: .thumbnailURL)
        self.downloadDate = (try? c.decode(String.self, forKey: .downloadDate)) ?? ""
        self.filePath = try? c.decodeIfPresent(String.self, forKey: .filePath)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(url, forKey: .url)
        try c.encodeIfPresent(thumbnailURL, forKey: .thumbnailURL)
        try c.encode(downloadDate, forKey: .downloadDate)
        try c.encodeIfPresent(filePath, forKey: .filePath)
    }
}

enum Formatting {
    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite else { return "N/A" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%02d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    static func count(_ value: Int?) -> String {
        guard let value else { return "N/A" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Turns ffprobe's raw bits-per-second string into "2.5 Mbps" / "128 kbps".
    static func bitrate(_ raw: String) -> String {
        guard let bps = Double(raw), bps > 0 else { return raw.isEmpty ? "N/A" : raw }
        if bps >= 1_000_000 { return String(format: "%.1f Mbps", bps / 1_000_000) }
        if bps >= 1_000 { return String(format: "%.0f kbps", bps / 1_000) }
        return String(format: "%.0f bps", bps)
    }

    static func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/*?:\"<>|")
        return String(name.unicodeScalars.filter { !invalid.contains($0) })
    }
}
