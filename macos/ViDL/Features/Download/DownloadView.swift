import SwiftUI

struct DownloadView: View {
    @Environment(AppState.self) private var app
    @Environment(HistoryStore.self) private var history
    @Environment(AppSettings.self) private var settings
    @Bindable var vm: DownloadViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if vm.hasMissingBinaries {
                        WarningBanner(title: app.tr("yt-dlp est introuvable. Installez-le pour analyser et télécharger :",
                                                    "yt-dlp not found. Install it to analyze and download:"),
                                      command: "brew install yt-dlp")
                    }
                    if vm.hasMissingFFmpeg {
                        WarningBanner(title: app.tr("ffmpeg est introuvable. Il est requis pour assembler les MP4 et extraire les MP3 :",
                                                    "ffmpeg not found. It's required to merge MP4s and extract MP3s:"),
                                      command: "brew install ffmpeg")
                    }
                    analyzeCard
                    if vm.meta != nil {
                        infoCard
                        optionsCard
                    }
                }
                .padding(28)
            }
            .scrollContentBackground(.hidden)
            if vm.phase.footerVisible {
                progressFooter
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let dropped = urls.first(where: { $0.scheme == "http" || $0.scheme == "https" }) else { return false }
            vm.url = dropped.absoluteString
            Task { await vm.analyze() }
            return true
        }
        .onAppear { vm.app = app; vm.settings = settings }
        .onChange(of: app.pendingURL) { _, newValue in
            guard let newValue, !newValue.isEmpty else { return }
            vm.url = newValue
            app.pendingURL = nil
            Task { await vm.analyze() }
        }
        .alert(app.tr("Attention", "Warning"),
               isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(app.tr("Téléchargement", "Download"))
                .font(.rounded(28, .bold)).foregroundStyle(.white)
            Text(app.tr("Analysez une vidéo et choisissez votre format.",
                        "Analyze a video and pick your format."))
                .font(.rounded(13)).foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Analyze

    private var analyzeCard: some View {
        @Bindable var vm = vm
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(symbol: "magnifyingglass", title: app.tr("Analyse de la vidéo", "Video Analysis"))
                HStack(spacing: 10) {
                    TextField(app.tr("Entrez l'URL de la vidéo…", "Enter the video URL…"), text: $vm.url)
                        .textFieldStyle(.plain)
                        .font(.rounded(13))
                        .foregroundStyle(.white)
                        .fieldBackground()
                        .onSubmit { Task { await vm.analyze() } }
                    Button {
                        if let s = NSPasteboard.general.string(forType: .string) { vm.url = s }
                    } label: { Image(systemName: "doc.on.clipboard") }
                        .buttonStyle(IconButtonStyle())
                        .help(app.tr("Coller", "Paste"))
                        .accessibilityLabel(app.tr("Coller l'URL", "Paste URL"))
                    Button {
                        Task { await vm.analyze() }
                    } label: {
                        HStack(spacing: 6) {
                            if vm.analyzing { ProgressView().controlSize(.small).tint(.white) }
                            else { Image(systemName: "sparkle.magnifyingglass") }
                            Text(app.tr("Analyser", "Analyze"))
                        }
                    }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(vm.analyzing)
                }
                if !vm.analysisInfo.isEmpty {
                    Text(vm.analysisInfo).font(.rounded(11, .medium)).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    // MARK: - Video info

    private var infoCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack(alignment: .bottomTrailing) {
                    RemoteThumbnail(urlString: vm.meta?.thumbnailURL, width: 220, height: 124)
                    Button {
                        vm.downloadThumbnail()
                    } label: { Image(systemName: "arrow.down.to.line") }
                        .buttonStyle(IconButtonStyle())
                        .padding(6)
                        .help(app.tr("Télécharger la miniature", "Download thumbnail"))
                        .accessibilityLabel(app.tr("Télécharger la miniature", "Download thumbnail"))
                }
                VStack(alignment: .leading, spacing: 7) {
                    if let title = vm.meta?.title {
                        titleWithStatus(title)
                            .font(.rounded(16, .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .help(vm.justDownloaded ? app.tr("Téléchargée", "Downloaded") : "")
                            .accessibilityLabel(vm.justDownloaded
                                                ? app.tr("\(title) — téléchargée", "\(title) — downloaded")
                                                : title)
                    }
                    if let ch = vm.meta?.uploader {
                        InfoRow(label: app.tr("Chaîne", "Channel"), value: ch)
                    }
                    if let date = vm.meta?.uploadDate {
                        InfoRow(label: "Date", value: date)
                    }
                    if let d = vm.meta?.duration {
                        InfoRow(label: app.tr("Durée", "Duration"), value: Formatting.duration(d))
                    }
                    HStack(spacing: 16) {
                        if let v = vm.meta?.viewCount {
                            InfoRow(label: app.tr("Vues", "Views"), value: Formatting.count(v))
                        }
                        if let l = vm.meta?.likeCount {
                            InfoRow(label: "Likes", value: Formatting.count(l))
                        }
                        if let c = vm.meta?.commentCount {
                            InfoRow(label: app.tr("Commentaires", "Comments"), value: Formatting.count(c))
                        }
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - Options

    private var optionsCard: some View {
        @Bindable var vm = vm
        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(symbol: "slider.horizontal.3", title: app.tr("Options de téléchargement", "Download Options"))

                HStack(spacing: 10) {
                    Picker("", selection: $vm.exportType) {
                        Text("MP4").tag(ExportType.mp4)
                        Text("MP3").tag(ExportType.mp3)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()   // intrinsic width, flush-left with the section header & Dossier
                    .accessibilityLabel(app.tr("Format d'export", "Export format"))
                    .onChange(of: vm.exportType) { _, _ in vm.onExportTypeChange() }

                    Text("Format")
                        .font(.rounded(12, .medium)).foregroundStyle(.white.opacity(0.6))

                    if vm.exportType == .mp4 {
                        Picker("", selection: $vm.selectedVideoFormatID) {
                            ForEach(vm.videoFormats) { f in
                                Text(formatLabel(f)).tag(Optional(f.id))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        .accessibilityLabel("Format")
                    } else {
                        Picker("", selection: $vm.mp3Bitrate) {
                            ForEach(DownloadViewModel.mp3Bitrates, id: \.self) { b in
                                Text("\(b) kbps").tag(b)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        .accessibilityLabel("Format")
                    }

                    Spacer()

                    Text(app.tr("Langue audio", "Audio language"))
                        .font(.rounded(12, .medium)).foregroundStyle(.white.opacity(0.6))
                    Picker("", selection: $vm.audioLanguage) {
                        ForEach(DownloadViewModel.audioLanguages, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                    .accessibilityLabel(app.tr("Langue audio", "Audio language"))
                }

                HStack(spacing: 12) {
                    Button {
                        vm.chooseFolder()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                            Text(app.tr("Dossier", "Folder"))
                        }
                    }
                    .buttonStyle(GhostButtonStyle())
                    Text((vm.outputDirPath as NSString).abbreviatingWithTildeInPath)
                        .font(.rounded(11)).foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Toggle(app.tr("Ouvrir à la fin", "Open when done"), isOn: $vm.openFolderAfter)
                        .toggleStyle(.switch)
                        .font(.rounded(12))
                        .foregroundStyle(.white.opacity(0.7))
                }

                HStack(spacing: 12) {
                    if vm.phase.isTransferring {
                        Button {
                            vm.cancelDownload()
                        } label: {
                            HStack(spacing: 6) { Image(systemName: "xmark"); Text(app.tr("Annuler", "Cancel")) }
                        }
                        .buttonStyle(GhostButtonStyle(tint: Theme.danger))
                        .keyboardShortcut(.cancelAction)
                    }
                    Spacer()
                    Button {
                        Task { await vm.download(history: history) }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text(app.tr("Télécharger", "Download"))
                        }
                    }
                    .buttonStyle(AccentButtonStyle(gradient: Theme.successGradient))
                    .keyboardShortcut(.defaultAction)
                    .disabled(vm.phase.isBusy || vm.meta == nil)
                    .help(vm.meta == nil ? app.tr("Analysez une vidéo d'abord", "Analyze a video first") : "")
                }
            }
        }
    }

    private var progressFooter: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.white.opacity(0.08))
            VStack(alignment: .leading, spacing: 9) {
                ZStack {
                    NeonProgressBar(value: vm.displayProgress,
                                    gradient: vm.displayProgress >= 99.5 ? Theme.successGradient : Theme.accentGradient,
                                    animated: false)
                    if vm.phase.showsIndeterminate {
                        IndeterminateBar()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: vm.phase.showsIndeterminate)
                HStack(spacing: 10) {
                    Text(vm.statusLine).font(.rounded(12, .medium)).foregroundStyle(.white.opacity(0.7))
                    if !vm.detailLine.isEmpty {
                        Text(vm.detailLine)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    if vm.phase.revealableFile != nil {
                        Button {
                            vm.revealFolder()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                Text(app.tr("Afficher dans le Finder", "Show in Finder"))
                            }
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                    if vm.phase.offersReencode || vm.phase.isReencoding {
                        Button {
                            Task { await vm.reencode() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: vm.phase.isReencoding ? "stop.fill" : "film")
                                Text(vm.phase.isReencoding ? app.tr("Arrêter", "Stop") : app.tr("Re-encoder MP4", "Re-encode MP4"))
                            }
                        }
                        .buttonStyle(GhostButtonStyle(tint: Theme.accent))
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
        }
        .background(.ultraThinMaterial)
    }

    /// The video title with an inline green seal appended once it's been downloaded,
    /// so confirming success never adds a row that shoves the options under the footer.
    private func titleWithStatus(_ title: String) -> Text {
        guard vm.justDownloaded else { return Text(title) }
        return Text(title) + Text("  ")
            + Text(Image(systemName: "checkmark.seal.fill")).foregroundColor(Theme.success)
    }

    private func formatLabel(_ f: VideoFormat) -> String {
        let p = min(f.width, f.height)   // vertical resolution, even for portrait video
        var s = "\(p)p · \(f.fps) fps"
        if let d = vm.meta?.duration {
            let mb = Double(f.tbr) * d / 8192
            s += String(format: " · ~%.0f MB", mb)
        }
        return s
    }
}
