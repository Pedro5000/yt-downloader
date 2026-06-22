import SwiftUI
import Observation

enum AppLanguage: String, CaseIterable {
    case fr, en
}

enum AppTab: String, CaseIterable, Identifiable {
    case download, history, conversion
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .download: return "arrow.down.circle.fill"
        case .history: return "clock.arrow.circlepath"
        case .conversion: return "wand.and.stars"
        }
    }
}

@Observable
@MainActor
final class AppState {
    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") }
    }
    var selectedTab: AppTab = .download
    var showAbout = false

    /// Set by the History tab to hand a URL to the Download tab, which picks it up,
    /// pre-fills the field, analyzes it, and clears this back to nil.
    var pendingURL: String?

    init() {
        let saved = UserDefaults.standard.string(forKey: "language")
        self.language = AppLanguage(rawValue: saved ?? "fr") ?? .fr
    }

    /// Routes a URL to the Download tab for re-use (e.g. from a history entry).
    func openInDownload(_ url: String) {
        pendingURL = url
        selectedTab = .download
    }

    /// Picks the correct string for the active language. Mirrors the Python `if fr else en` pattern.
    func tr(_ fr: String, _ en: String) -> String {
        language == .fr ? fr : en
    }

    func tabTitle(_ tab: AppTab) -> String {
        switch tab {
        case .download: return tr("Téléchargement", "Download")
        case .history: return tr("Historique", "History")
        case .conversion: return tr("Conversion", "Conversion")
        }
    }
}
