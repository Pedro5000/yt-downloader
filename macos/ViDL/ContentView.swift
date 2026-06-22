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
                    .accessibilityHidden(app.selectedTab != .download)
                HistoryView().opacity(app.selectedTab == .history ? 1 : 0)
                    .allowsHitTesting(app.selectedTab == .history)
                    .accessibilityHidden(app.selectedTab != .history)
                ConversionView(vm: conversionVM).opacity(app.selectedTab == .conversion ? 1 : 0)
                    .allowsHitTesting(app.selectedTab == .conversion)
                    .accessibilityHidden(app.selectedTab != .conversion)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.appBackground)
        .task { Notifier.requestAuthorizationIfNeeded() }
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
                        .font(.rounded(10, .medium)).foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 28)
            .padding(.bottom, 26)

            VStack(spacing: 4) {
                ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                    SidebarItem(tab: tab, isSelected: app.selectedTab == tab) {
                        app.selectedTab = tab
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            HStack(spacing: 10) {
                LanguageToggle()
                SettingsButton()
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
    @State private var hovering = false

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
            .foregroundStyle(isSelected ? .white : Color.white.opacity(hovering ? 0.8 : 0.55))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Theme.accentGradient.opacity(0.9))
                                     : AnyShapeStyle(Color.white.opacity(hovering ? 0.06 : 0)))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct SettingsButton: View {
    @Environment(AppState.self) private var app
    @Environment(\.openSettings) private var openSettings
    @State private var hovering = false

    var body: some View {
        Button {
            openSettings()
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
        .help(app.tr("Réglages", "Settings"))
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

    /// App version from the bundle, so the About panel never drifts from the build.
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "play.square.stack.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accentGradient)
            Text("ViDL").font(.rounded(26, .bold)).foregroundStyle(.white)
            Text(app.tr("Téléchargeur universel · Version \(Self.appVersion)",
                        "Universal Downloader · Version \(Self.appVersion)"))
                .font(.rounded(12, .medium)).foregroundStyle(.white.opacity(0.6))
            Text("© 2026").font(.rounded(11)).foregroundStyle(.white.opacity(0.4))

            Text(app.tr("La mise à jour de yt-dlp est dans les Réglages.",
                        "Updating yt-dlp is in Settings."))
                .font(.rounded(11)).foregroundStyle(.white.opacity(0.4))
                .padding(.top, 2)

            Button(app.tr("Fermer", "Close")) { dismiss() }
                .buttonStyle(AccentButtonStyle())
                .padding(.top, 6)
        }
        .padding(36)
        .frame(width: 340)
        .background(Theme.appBackground)
    }
}
