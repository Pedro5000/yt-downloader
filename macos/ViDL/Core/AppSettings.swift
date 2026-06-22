import SwiftUI
import Observation

/// Browser yt-dlp pulls cookies from for sign-in/age-restricted videos.
enum CookiesBrowser: String, CaseIterable, Identifiable {
    case none, firefox, chrome, safari, brave, edge
    var id: String { rawValue }

    /// Brand name for the picker ("" for `.none`, localized in the view).
    var brandLabel: String {
        switch self {
        case .none:    return ""
        case .firefox: return "Firefox"
        case .chrome:  return "Chrome"
        case .safari:  return "Safari"
        case .brave:   return "Brave"
        case .edge:    return "Edge"
        }
    }

    /// Value passed to `--cookies-from-browser`, or nil when cookies are disabled.
    var ytDlpValue: String? { self == .none ? nil : rawValue }
}

/// App-wide preferences, shared by the main window and the Settings scene.
@Observable
@MainActor
final class AppSettings {
    var cookiesBrowser: CookiesBrowser {
        didSet { UserDefaults.standard.set(cookiesBrowser.rawValue, forKey: "cookiesBrowser") }
    }
    /// Include VP9/AV1 (WebM) video formats — often the only 1440p/4K — exported as MKV.
    var includeAllFormats: Bool {
        didSet { UserDefaults.standard.set(includeAllFormats, forKey: "includeAllFormats") }
    }
    /// Show a system notification when a download/conversion finishes in the background.
    var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }
    /// Embed metadata, thumbnail and chapters into the downloaded file.
    var embedMetadata: Bool {
        didSet { UserDefaults.standard.set(embedMetadata, forKey: "embedMetadata") }
    }
    /// Remove SponsorBlock segments (sponsors, self-promo, interaction reminders).
    var sponsorBlock: Bool {
        didSet { UserDefaults.standard.set(sponsorBlock, forKey: "sponsorBlock") }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "cookiesBrowser")
        // Default to Firefox to preserve the previous hard-coded behavior.
        self.cookiesBrowser = CookiesBrowser(rawValue: saved ?? "firefox") ?? .firefox
        self.includeAllFormats = UserDefaults.standard.bool(forKey: "includeAllFormats")
        self.notificationsEnabled = (UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool) ?? true
        self.embedMetadata = UserDefaults.standard.bool(forKey: "embedMetadata")
        self.sponsorBlock = UserDefaults.standard.bool(forKey: "sponsorBlock")
    }
}
