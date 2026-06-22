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

            Section {
                Toggle(app.tr("Inclure les formats VP9/AV1 (qualité max)",
                              "Include VP9/AV1 formats (max quality)"),
                       isOn: $settings.includeAllFormats)
            } header: {
                Text(app.tr("Formats avancés", "Advanced formats"))
            } footer: {
                Text(app.tr("Affiche les résolutions 1440p/4K disponibles uniquement en VP9/AV1. Ces fichiers sont exportés en MKV (non lus par QuickTime/Final Cut sans conversion).",
                            "Shows 1440p/4K resolutions only available as VP9/AV1. These are exported as MKV (not playable by QuickTime/Final Cut without conversion)."))
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 380)
        .navigationTitle(app.tr("Réglages", "Settings"))
    }
}
