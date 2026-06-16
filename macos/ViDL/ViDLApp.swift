import SwiftUI

@main
struct ViDLApp: App {
    @State private var appState = AppState()
    @State private var history = HistoryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(history)
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
    }
}
