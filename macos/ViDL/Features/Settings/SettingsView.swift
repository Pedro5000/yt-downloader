import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker(app.tr("Navigateur pour les cookies", "Cookies browser"),
                       selection: $settings.cookiesBrowser) {
                    ForEach(CookiesBrowser.allCases) { browser in
                        Text(browser == .none ? app.tr("Aucun", "None") : browser.brandLabel)
                            .tag(browser)
                    }
                }
            } header: {
                Text(app.tr("Vidéos avec connexion / restriction d'âge",
                            "Sign-in / age-restricted videos"))
            } footer: {
                Text(app.tr("Utilisé en repli pour les vidéos nécessitant une connexion. Vous devez être connecté à YouTube dans ce navigateur. « Aucun » désactive cette tentative.",
                            "Used as a fallback for videos that require a sign-in. You must be logged into YouTube in that browser. “None” disables that attempt."))
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 260)
        .navigationTitle(app.tr("Réglages", "Settings"))
    }
}
