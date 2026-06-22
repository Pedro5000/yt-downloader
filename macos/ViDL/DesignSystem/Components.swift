import SwiftUI

// MARK: - Glass card

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }
            }
            .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
    }
}

// MARK: - Buttons

struct AccentButtonStyle: ButtonStyle {
    var gradient: LinearGradient = Theme.accentGradient
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration, gradient: gradient) }

    struct Inner: View {
        let configuration: ButtonStyleConfiguration
        let gradient: LinearGradient
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.rounded(13, .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(gradient)
                    if hovering {
                        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.12))
                    }
                }
                .opacity(configuration.isPressed ? 0.85 : 1)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

struct GhostButtonStyle: ButtonStyle {
    var tint: Color = .white
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration, tint: tint) }

    struct Inner: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.rounded(13, .medium))
                .foregroundStyle(tint.opacity(0.92))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white.opacity(configuration.isPressed ? 0.16 : (hovering ? 0.11 : 0.07)))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(Color.white.opacity(hovering ? 0.16 : 0.10), lineWidth: 1)
                        }
                }
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration) }

    struct Inner: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .frame(width: 30, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(configuration.isPressed ? 0.18 : (hovering ? 0.12 : 0.06)))
                }
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.85))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

// MARK: - Progress bar

struct NeonProgressBar: View {
    var value: Double            // 0...100
    var gradient: LinearGradient = Theme.accentGradient
    var height: CGFloat = 12
    var animated: Bool = true    // false when the value is already eased at ~60fps upstream

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(gradient)
                    .frame(width: max(0, min(1, value / 100)) * geo.size.width)
                    .shadow(color: Theme.accent.opacity(0.5), radius: 6)
                    .animation(animated ? .easeOut(duration: 0.18) : nil, value: value)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Indeterminate progress (preparing phase)

struct IndeterminateBar: View {
    var gradient: LinearGradient = Theme.accentGradient
    var height: CGFloat = 12
    @State private var t: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let segW = max(40, w * 0.32)
            let travel = w + segW
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(gradient)
                    .frame(width: segW)
                    .offset(x: -segW + t * travel)
                    .shadow(color: Theme.accent.opacity(0.5), radius: 6)
            }
            .clipShape(Capsule())
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) {
                    t = 1
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Warning banner (missing binary, etc.)

struct WarningBanner: View {
    var title: String
    var command: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18)).foregroundStyle(Theme.danger)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.rounded(13, .semibold)).foregroundStyle(.white)
                Text(command)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .textSelection(.enabled)
            }
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: { Image(systemName: "doc.on.clipboard") }
                .buttonStyle(IconButtonStyle())
                .help("Copier")
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.danger.opacity(0.14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.danger.opacity(0.4), lineWidth: 1)
                }
        }
    }
}

// MARK: - Missing-dependency banner with in-app install

struct DependencyBanner: View {
    @Environment(AppState.self) private var app
    let message: String
    let command: String        // e.g. "brew install yt-dlp"
    let packages: [String]     // e.g. ["yt-dlp"]
    var onInstalled: () -> Void = {}
    @State private var installer = Installer()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18)).foregroundStyle(Theme.danger)
                VStack(alignment: .leading, spacing: 4) {
                    Text(message).font(.rounded(13, .semibold)).foregroundStyle(.white)
                    Text(command)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7)).textSelection(.enabled)
                }
                Spacer()
                if installer.running {
                    ProgressView().controlSize(.small).tint(.white)
                } else if installer.lastResult == true {
                    Label(app.tr("Installé", "Installed"), systemImage: "checkmark.circle.fill")
                        .font(.rounded(12, .semibold)).foregroundStyle(Theme.success)
                } else if let brew = BinaryLocator.brew {
                    Button(app.tr("Installer", "Install")) {
                        Task { await installer.install(packages, brew: brew); if installer.lastResult == true { onInstalled() } }
                    }
                    .buttonStyle(AccentButtonStyle())
                } else {
                    Button(app.tr("Installer Homebrew", "Install Homebrew")) {
                        if let url = URL(string: "https://brew.sh") { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(GhostButtonStyle())
                }
            }
            if installer.running, !installer.lastLine.isEmpty {
                Text(installer.lastLine)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5)).lineLimit(1).truncationMode(.middle)
            }
            if installer.lastResult == false {
                Text(app.tr("L'installation a échoué. Lancez la commande dans le Terminal.",
                            "Installation failed. Run the command in Terminal."))
                    .font(.rounded(12)).foregroundStyle(Theme.danger)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.danger.opacity(0.14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.danger.opacity(0.4), lineWidth: 1)
                }
        }
    }
}

// MARK: - Section header

struct SectionHeader: View {
    var symbol: String
    var title: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.rounded(13, .semibold))
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
        }
    }
}

// MARK: - Info row

struct InfoRow: View {
    var label: String
    var value: String
    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.rounded(12, .medium))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.rounded(12, .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

// MARK: - Async remote thumbnail

struct RemoteThumbnail: View {
    let urlString: String?
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat = 10

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.06))
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: min(width, height) * 0.32))
                .foregroundStyle(.white.opacity(0.25))
        }
    }
}

// MARK: - Styled field background

struct FieldBackground: ViewModifier {
    var focused: Bool = false
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.black.opacity(0.25))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(focused ? Theme.accent.opacity(0.85) : Color.white.opacity(0.08),
                                    lineWidth: focused ? 1.5 : 1)
                    }
            }
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}

extension View {
    func fieldBackground(focused: Bool = false) -> some View { modifier(FieldBackground(focused: focused)) }
}

// MARK: - Drag-and-drop hint overlay

struct DropHint: View {
    var text: String
    var body: some View {
        ZStack {
            Theme.accent.opacity(0.08)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [9]))
                .foregroundStyle(Theme.accent)
                .padding(10)
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 34))
                Text(text).font(.rounded(15, .semibold))
            }
            .foregroundStyle(Theme.accent)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
