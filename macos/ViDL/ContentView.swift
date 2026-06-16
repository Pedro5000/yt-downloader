import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var app
    // Owned here so analyzed state survives tab switches.
    @State private var downloadVM = DownloadViewModel()
    @State private var conversionVM = ConversionViewModel()

    var body: some View {
        @Bindable var app = app
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 220)
            Divider().overlay(Color.white.opacity(0.06))
            ZStack {
                DownloadView(vm: downloadVM).opacity(app.selectedTab == .download ? 1 : 0)
                    .allowsHitTesting(app.selectedTab == .download)
                HistoryView().opacity(app.selectedTab == .history ? 1 : 0)
                    .allowsHitTesting(app.selectedTab == .history)
                ConversionView(vm: conversionVM).opacity(app.selectedTab == .conversion ? 1 : 0)
                    .allowsHitTesting(app.selectedTab == .conversion)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.appBackground)
        .sheet(isPresented: $app.showAbout) { AboutView() }
    }
}

private struct Sidebar: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "play.square.stack.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accentGradient)
                VStack(alignment: .leading, spacing: 0) {
                    Text("ViDL").font(.rounded(20, .bold)).foregroundStyle(.white)
                    Text(app.tr("Téléchargeur universel", "Universal Downloader"))
                        .font(.rounded(10, .medium)).foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 28)
            .padding(.bottom, 26)

            VStack(spacing: 4) {
                ForEach(AppTab.allCases) { tab in
                    SidebarItem(tab: tab, isSelected: app.selectedTab == tab) {
                        app.selectedTab = tab
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            HStack(spacing: 10) {
                LanguageToggle()
                AboutButton()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial.opacity(0.4))
    }
}

private struct SidebarItem: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void
    @Environment(AppState.self) private var app

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                Text(app.tabTitle(tab))
                    .font(.rounded(14, .medium))
                Spacer()
            }
            .foregroundStyle(isSelected ? .white : Color.white.opacity(0.55))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Theme.accentGradient.opacity(0.9)) : AnyShapeStyle(Color.clear))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AboutButton: View {
    @Environment(AppState.self) private var app
    @State private var hovering = false

    var body: some View {
        Button {
            app.showAbout = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(hovering ? Theme.accent : Color.white.opacity(0.5))
                .frame(width: 32, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(hovering ? 0.10 : 0.05))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(app.tr("À propos & mise à jour", "About & update"))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct LanguageToggle: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppLanguage.allCases, id: \.self) { lang in
                Button {
                    app.language = lang
                } label: {
                    Text(lang.rawValue.uppercased())
                        .font(.rounded(12, .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(app.language == lang ? .white : Color.white.opacity(0.45))
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(app.language == lang ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.clear))
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.25))
        }
    }
}

private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @State private var updating = false
    @State private var updateResult: (ok: Bool, text: String)?
    @State private var installedVersion: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "play.square.stack.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accentGradient)
            Text("ViDL").font(.rounded(26, .bold)).foregroundStyle(.white)
            Text(app.tr("Téléchargeur universel · Version 2.0", "Universal Downloader · Version 2.0"))
                .font(.rounded(12, .medium)).foregroundStyle(.white.opacity(0.6))
            Text("© 2026").font(.rounded(11)).foregroundStyle(.white.opacity(0.4))

            Divider().overlay(Color.white.opacity(0.1)).padding(.vertical, 4)

            Button {
                Task { await updateYtDlp() }
            } label: {
                HStack(spacing: 6) {
                    if updating { ProgressView().controlSize(.small).tint(.white) }
                    else { Image(systemName: "arrow.triangle.2.circlepath") }
                    Text(app.tr("Mettre à jour yt-dlp", "Update yt-dlp"))
                }
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(updating)
            // Fixed-height slot, always meaningfully filled (installed version → result).
            ZStack {
                if let updateResult {
                    HStack(spacing: 8) {
                        Image(systemName: updateResult.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(updateResult.ok ? Theme.success : Theme.danger)
                        Text(updateResult.text)
                            .font(.rounded(12, .medium))
                            .foregroundStyle(.white.opacity(0.78))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill((updateResult.ok ? Theme.success : Theme.danger).opacity(0.12))
                    }
                    .transition(.opacity)
                } else {
                    Text(installedVersion.map { "yt-dlp · \($0)" } ?? " ")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .transition(.opacity)
                }
            }
            .frame(height: 44)

            Button(app.tr("Fermer", "Close")) { dismiss() }
                .buttonStyle(AccentButtonStyle())
        }
        .padding(36)
        .frame(width: 340)
        .background(Theme.appBackground)
        .task { await loadVersion() }
    }

    private func loadVersion() async {
        guard let ytDlp = BinaryLocator.ytDlp else { return }
        let res = await Shell.capture(ytDlp, ["--version"])
        let v = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !v.isEmpty { withAnimation { installedVersion = v } }
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
