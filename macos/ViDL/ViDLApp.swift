import SwiftUI

@main
struct ViDLApp: App {
    @State private var appState = AppState()
    @State private var history = HistoryStore()
    @State private var settings = AppSettings()

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
