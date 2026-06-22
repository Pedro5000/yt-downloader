import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var app

    @State private var ytdlpVersion: String?
    @State private var updating = false
    @State private var updateResult: (ok: Bool, text: String)?
    @State private var installer = Installer()

    var body: some View {
        @Bindable var settings = settings
        Form {
            dependenciesSection
            cookiesSection
            formatsSection
            notificationsSection(settings: $settings)
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 560)
        .navigationTitle(app.tr("Réglages", "Settings"))
        .task { await loadVersion() }
    }

    // MARK: - Dependencies (status + update / install)

    private var dependenciesSection: some View {
        Section {
            HStack {
                Label {
                    Text("yt-dlp")
                    if let r = updateResult {
                        Text(r.text)
                            .font(.caption)
                            .foregroundStyle(r.ok ? Theme.success : Theme.danger)
                    } else if let v = ytdlpVersion {
                        Text(v).foregroundStyle(.secondary).font(.system(.caption, design: .monospaced))
                    }
                } icon: {
                    statusIcon(present: BinaryLocator.ytDlp != nil)
                }
                Spacer()
                if BinaryLocator.ytDlp != nil {
                    Button { Task { await updateYtDlp() } } label: {
                        if updating { ProgressView().controlSize(.small) }
                        else { Text(app.tr("Mettre à jour", "Update")) }
                    }
                    .disabled(updating)
                } else {
                    installButton(["yt-dlp"])
                }
            }

            HStack {
                Label("ffmpeg", systemImage: BinaryLocator.ffmpeg != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(BinaryLocator.ffmpeg != nil ? Theme.success : Theme.danger)
                Spacer()
                if BinaryLocator.ffmpeg == nil { installButton(["ffmpeg"]) }
            }

            if installer.running, !installer.lastLine.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(installer.lastLine)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
        } header: {
            Text(app.tr("Dépendances", "Dependencies"))
        } footer: {
            if BinaryLocator.brew == nil {
                Text(app.tr("Homebrew introuvable — installez-le depuis brew.sh pour gérer yt-dlp et ffmpeg.",
                            "Homebrew not found — install it from brew.sh to manage yt-dlp and ffmpeg."))
            }
        }
    }

    private func statusIcon(present: Bool) -> some View {
        Image(systemName: present ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(present ? Theme.success : Theme.danger)
    }

    @ViewBuilder
    private func installButton(_ packages: [String]) -> some View {
        if let brew = BinaryLocator.brew {
            Button(app.tr("Installer", "Install")) {
                Task { await installer.install(packages, brew: brew) }
            }
            .disabled(installer.running)
        } else {
            Button(app.tr("Installer Homebrew", "Install Homebrew")) {
                if let url = URL(string: "https://brew.sh") { NSWorkspace.shared.open(url) }
            }
        }
    }

    // MARK: - Cookies

    private var cookiesSection: some View {
        @Bindable var settings = settings
        return Section {
            Picker(app.tr("Navigateur pour les cookies", "Cookies browser"),
                   selection: $settings.cookiesBrowser) {
                ForEach(CookiesBrowser.allCases) { browser in
                    Text(browser == .none ? app.tr("Aucun", "None") : browser.brandLabel).tag(browser)
                }
            }
        } header: {
            Text(app.tr("Vidéos avec connexion / restriction d'âge", "Sign-in / age-restricted videos"))
        } footer: {
            Text(app.tr("Utilisé en repli pour les vidéos nécessitant une connexion. Vous devez être connecté à YouTube dans ce navigateur. « Aucun » désactive cette tentative.",
                        "Used as a fallback for videos that require a sign-in. You must be logged into YouTube in that browser. “None” disables that attempt."))
        }
    }

    // MARK: - Advanced formats

    private var formatsSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(app.tr("Inclure les formats VP9/AV1 (qualité max)", "Include VP9/AV1 formats (max quality)"),
                   isOn: $settings.includeAllFormats)
        } header: {
            Text(app.tr("Formats avancés", "Advanced formats"))
        } footer: {
            Text(app.tr("Affiche les résolutions 1440p/4K disponibles uniquement en VP9/AV1. Ces fichiers sont exportés en MKV (non lus par QuickTime/Final Cut sans conversion).",
                        "Shows 1440p/4K resolutions only available as VP9/AV1. These are exported as MKV (not playable by QuickTime/Final Cut without conversion)."))
        }
    }

    // MARK: - Notifications

    private func notificationsSection(settings: Bindable<AppSettings>) -> some View {
        Section {
            Toggle(app.tr("Notifier à la fin d'une tâche", "Notify when a task finishes"),
                   isOn: settings.notificationsEnabled)
        } header: {
            Text(app.tr("Notifications", "Notifications"))
        } footer: {
            Text(app.tr("Notification système quand un téléchargement ou une conversion se termine alors que l'app est en arrière-plan.",
                        "System notification when a download or conversion finishes while the app is in the background."))
        }
    }

    // MARK: - yt-dlp version / update

    private func loadVersion() async {
        guard let ytDlp = BinaryLocator.ytDlp else { return }
        let res = await Shell.capture(ytDlp, ["--version"])
        let v = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !v.isEmpty { withAnimation { ytdlpVersion = v } }
    }

    private func updateYtDlp() async {
        guard let ytDlp = BinaryLocator.ytDlp else {
            updateResult = (false, app.tr("yt-dlp est introuvable.", "yt-dlp not found."))
            return
        }
        updating = true
        updateResult = nil
        let res = await Shell.capture(ytDlp, ["-U"])
        updating = false

        let combined = res.combined
        let lower = combined.lowercased()
        let version = combined.range(of: #"[0-9]{4}\.[0-9]{2}\.[0-9]{2}"#, options: .regularExpression)
            .map { String(combined[$0]) }

        withAnimation {
            if lower.contains("up to date") {
                updateResult = (true, version.map { app.tr("Déjà à jour — version \($0).", "Already up to date — version \($0).") }
                    ?? app.tr("yt-dlp est déjà à jour.", "yt-dlp is already up to date."))
            } else if lower.contains("updated yt-dlp") || lower.contains("updating to") || lower.contains("has been updated") {
                updateResult = (true, version.map { app.tr("Mis à jour vers la version \($0).", "Updated to version \($0).") }
                    ?? app.tr("yt-dlp a été mis à jour.", "yt-dlp has been updated."))
                Task { await loadVersion() }
            } else if lower.contains("package manager") || lower.contains("pip") || lower.contains("brew") || lower.contains("homebrew") {
                updateResult = (false, app.tr("Installé via Homebrew — lancez : brew upgrade yt-dlp",
                                              "Installed via Homebrew — run: brew upgrade yt-dlp"))
            } else if !res.succeeded || lower.contains("error") {
                updateResult = (false, app.tr("Échec de la mise à jour de yt-dlp.", "Failed to update yt-dlp."))
            } else {
                updateResult = (true, app.tr("Mise à jour terminée.", "Update complete."))
            }
        }
    }
}
