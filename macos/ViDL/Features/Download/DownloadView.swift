import SwiftUI

struct DownloadView: View {
    @Environment(AppState.self) private var app
    @Environment(HistoryStore.self) private var history
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
                    analyzeCard
                    if vm.meta != nil { infoCard }
                    optionsCard
                }
                .padding(28)
            }
            .scrollContentBackground(.hidden)
            if vm.downloading || vm.progress > 0 || !vm.statusText.isEmpty {
                progressFooter
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let dropped = urls.first(where: { $0.scheme == "http" || $0.scheme == "https" }) else { return false }
            vm.url = dropped.absoluteString
            Task { await vm.analyze() }
            return true
        }
        .onAppear { vm.app = app }
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
                }
                VStack(alignment: .leading, spacing: 7) {
                    if let title = vm.meta?.title {
                        Text(title).font(.rounded(16, .bold)).foregroundStyle(.white)
                            .lineLimit(2)
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

                Picker("", selection: $vm.exportType) {
                    Text("MP4").tag(ExportType.mp4)
                    Text("MP3").tag(ExportType.mp3)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
                .onChange(of: vm.exportType) { _, _ in vm.onExportTypeChange() }

                HStack(spacing: 10) {
                    Text(app.tr("Format d'origine", "Source format"))
                        .font(.rounded(12, .medium)).foregroundStyle(.white.opacity(0.6))
                    if vm.exportType == .mp4 {
                        Picker("", selection: $vm.selectedVideoFormatID) {
                            ForEach(vm.videoFormats) { f in
                                Text(formatLabel(f)).tag(Optional(f.id))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 320)
                    } else {
                        Picker("", selection: $vm.selectedAudioFormatID) {
                            ForEach(vm.audioFormats) { f in
                                Text(f.label).tag(Optional(f.id))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 320)
                    }
                    Spacer()
                    Text(app.tr("Langue audio", "Audio language"))
                        .font(.rounded(12, .medium)).foregroundStyle(.white.opacity(0.6))
                    Picker("", selection: $vm.audioLanguage) {
                        ForEach(DownloadViewModel.audioLanguages, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 110)
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
                        .font(.rounded(11)).foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Toggle(app.tr("Ouvrir à la fin", "Open when done"), isOn: $vm.openFolderAfter)
                        .toggleStyle(.switch)
                        .font(.rounded(12))
                        .foregroundStyle(.white.opacity(0.7))
                }

                HStack(spacing: 12) {
                    if vm.downloading {
                        Button {
                            vm.cancelDownload()
                        } label: {
                            HStack(spacing: 6) { Image(systemName: "xmark"); Text(app.tr("Annuler", "Cancel")) }
                        }
                        .buttonStyle(GhostButtonStyle(tint: Theme.danger))
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
                    .disabled(vm.downloading)
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
                    if vm.downloading && vm.progress <= 0 {
                        IndeterminateBar()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: vm.progress <= 0)
                HStack(spacing: 10) {
                    Text(vm.statusText).font(.rounded(12, .medium)).foregroundStyle(.white.opacity(0.7))
                    if !downloadDetail.isEmpty {
                        Text(downloadDetail)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                    if vm.showReencode {
                        Button {
                            Task { await vm.reencode() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: vm.encoding ? "stop.fill" : "film")
                                Text(vm.encoding ? app.tr("Arrêter", "Stop") : app.tr("Re-encoder MP4", "Re-encode MP4"))
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

    private var downloadDetail: String {
        var parts: [String] = []
        if !vm.percentText.isEmpty { parts.append(vm.percentText) }
        if !vm.speedText.isEmpty { parts.append(vm.speedText) }
        if !vm.etaText.isEmpty { parts.append("ETA \(vm.etaText)") }
        return parts.joined(separator: " · ")
    }

    private func formatLabel(_ f: VideoFormat) -> String {
        var s = "\(f.width)x\(f.height), \(f.fps)fps, \(f.tbr) kbps"
        if let d = vm.meta?.duration {
            let mb = Double(f.tbr) * d / 8192
            s += String(format: ", ~%.0f MB", mb)
        }
        return s
    }
}
