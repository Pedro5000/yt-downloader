import SwiftUI

@main
struct ViDLApp: App {
    @State private var appState = AppState()
    @State private var history = HistoryStore()
    @State private var settings = AppSettings()

    init() {
        // Don't let macOS resurrect stray windows (e.g. a previously-open Settings
        // window) at launch — only the main window should open.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(history)
                .environment(settings)
                .frame(minWidth: 880, minHeight: 720)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(appState.tr("À propos de ViDL", "About ViDL")) {
                    appState.showAbout = true
                }
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
                .environment(settings)
                .preferredColorScheme(.dark)
        }
    }
}
