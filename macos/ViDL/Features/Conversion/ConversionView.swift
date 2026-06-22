import SwiftUI

struct ConversionView: View {
    @Environment(AppState.self) private var app
    @Environment(AppSettings.self) private var settings
    @Bindable var vm: ConversionViewModel
    @State private var dropTargeted = false
    @State private var depsRefresh = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if vm.hasMissingFFmpeg {
                    DependencyBanner(message: app.tr("ffmpeg est introuvable. Installez-le pour convertir.",
                                                     "ffmpeg not found. Install it to convert."),
                                     command: "brew install ffmpeg", packages: ["ffmpeg"],
                                     onInstalled: { depsRefresh.toggle() })
                }
                fileCard
                optionsCard
                if vm.converting || vm.progress > 0 || !vm.statusText.isEmpty {
                    progressCard
                }
            }
            .padding(28)
        }
        .scrollContentBackground(.hidden)
        .dropDestination(for: URL.self) { urls, _ in
            guard let file = urls.first(where: { $0.isFileURL && vm.isSupportedMedia($0) }) else { return false }
            Task { await vm.loadFile(path: file.path) }
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted { DropHint(text: app.tr("Déposez un fichier média ici", "Drop a media file here")) }
        }
        .animation(.easeOut(duration: 0.12), value: dropTargeted)
        .onAppear { vm.app = app; vm.appSettings = settings }
        .sheet(isPresented: $vm.showAdvanced) { AdvancedSettingsSheet(vm: vm) }
        .alert(app.tr("Attention", "Warning"),
               isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })) {
            Button("OK") { vm.errorMessage = nil }
        } message: { Text(vm.errorMessage ?? "") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(app.tr("Conversion", "Conversion"))
                .font(.rounded(28, .bold)).foregroundStyle(.white)
            Text(app.tr("Convertissez vos fichiers audio et vidéo.", "Convert your audio and video files."))
                .font(.rounded(13)).foregroundStyle(.white.opacity(0.5))
        }
    }

    private var fileCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 16) {
                Button {
                    if vm.filePath == nil { Task { await vm.chooseFile() } } else { vm.playFile() }
                } label: {
                    ZStack {
                        if let thumb = vm.thumbnail {
                            Image(nsImage: thumb).resizable().scaledToFill()
                                .frame(width: 220, height: 124)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 38)).foregroundStyle(.white.opacity(0.9))
                                .shadow(radius: 4)
                        } else {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .frame(width: 220, height: 124)
                                .overlay {
                                    VStack(spacing: 6) {
                                        Image(systemName: "plus.rectangle.on.folder")
                                            .font(.system(size: 26)).foregroundStyle(.white.opacity(0.4))
                                        Text(app.tr("Choisir un fichier", "Choose a file"))
                                            .font(.rounded(11, .medium)).foregroundStyle(.white.opacity(0.4))
                                    }
                                }
                        }
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 7) {
                    if let info = vm.fileInfo {
                        Text(info.fileName).font(.rounded(15, .bold)).foregroundStyle(.white).lineLimit(1)
                        InfoRow(label: app.tr("Durée", "Duration"), value: Formatting.duration(info.duration))
                        InfoRow(label: "Format", value: info.formatName)
                        InfoRow(label: app.tr("Résolution", "Resolution"), value: info.videoResolution)
                        InfoRow(label: app.tr("Débit", "Bit rate"), value: Formatting.bitrate(info.formatBitRate))
                        InfoRow(label: "Codec", value: "\(info.videoCodec) / \(info.audioCodec)")
                        Button {
                            Task { await vm.chooseFile() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text(app.tr("Changer le fichier", "Change file"))
                            }
                        }
                        .buttonStyle(GhostButtonStyle())
                        .padding(.top, 2)
                    } else {
                        Text(app.tr("Aucun fichier sélectionné.", "No file selected."))
                            .font(.rounded(13)).foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                }
                Spacer()
            }
        }
    }

    private var optionsCard: some View {
        @Bindable var vm = vm
        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(symbol: "slider.horizontal.3", title: app.tr("Options d'export", "Export Options"))
                if vm.isAudioOutput {
                    HStack(spacing: 24) {
                        labeledPicker(app.tr("Format", "Format"), selection: $vm.settings.outputFormat, options: ConversionViewModel.outputFormats)
                        labeledPicker(app.tr("Échantillonnage", "Sample rate"), selection: $vm.settings.sampleRate, options: ConversionViewModel.sampleRates)
                    }
                } else {
                    HStack(spacing: 24) {
                        labeledPicker(app.tr("Format", "Format"), selection: $vm.settings.outputFormat, options: ConversionViewModel.outputFormats)
                        labeledPicker(app.tr("Qualité", "Quality"), selection: $vm.settings.quality, options: ConversionViewModel.qualities)
                    }
                    HStack(spacing: 24) {
                        labeledPicker(app.tr("Résolution", "Resolution"), selection: $vm.settings.resolution, options: ConversionViewModel.resolutions)
                        labeledPicker(app.tr("Échantillonnage", "Sample rate"), selection: $vm.settings.sampleRate, options: ConversionViewModel.sampleRates)
                    }
                }
                HStack {
                    Button {
                        vm.showAdvanced = true
                    } label: {
                        HStack(spacing: 6) { Image(systemName: "gearshape.2"); Text(app.tr("Paramètres avancés", "Advanced Settings")) }
                    }
                    .buttonStyle(GhostButtonStyle())
                    Spacer()
                    if !vm.isAudioOutput {
                        Toggle(app.tr("Optimiser pour le streaming", "Optimize for streaming"), isOn: $vm.settings.optimizeStreaming)
                            .toggleStyle(.switch).font(.rounded(12)).foregroundStyle(.white.opacity(0.7))
                    }
                }
                HStack(spacing: 12) {
                    Button {
                        vm.chooseOutputFolder()
                    } label: {
                        HStack(spacing: 6) { Image(systemName: "folder"); Text(app.tr("Dossier", "Folder")) }
                    }
                    .buttonStyle(GhostButtonStyle())
                    Text(vm.outputDirPath.isEmpty ? app.tr("À côté du fichier source", "Next to source file")
                                                  : (vm.outputDirPath as NSString).abbreviatingWithTildeInPath)
                        .font(.rounded(11)).foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Toggle(app.tr("Ouvrir à la fin", "Open when done"), isOn: $vm.openWhenDone)
                        .toggleStyle(.switch).font(.rounded(12)).foregroundStyle(.white.opacity(0.7))
                }
                HStack(spacing: 12) {
                    if vm.converting {
                        Button { vm.cancelConversion() } label: {
                            HStack(spacing: 6) { Image(systemName: "xmark"); Text(app.tr("Annuler", "Cancel")) }
                        }
                        .buttonStyle(GhostButtonStyle(tint: Theme.danger))
                        .keyboardShortcut(.cancelAction)
                    }
                    Spacer()
                    Button {
                        Task { await vm.startConversion() }
                    } label: {
                        HStack(spacing: 7) { Image(systemName: "wand.and.stars"); Text(app.tr("Démarrer la conversion", "Start Conversion")) }
                    }
                    .buttonStyle(AccentButtonStyle(gradient: Theme.successGradient))
                    .keyboardShortcut(.defaultAction)
                    .disabled(vm.converting || vm.filePath == nil)
                    .help(vm.filePath == nil ? app.tr("Choisissez un fichier d'abord", "Choose a file first") : "")
                }
            }
        }
    }

    private var progressCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                NeonProgressBar(value: vm.progress,
                                gradient: vm.progress >= 100 ? Theme.successGradient : Theme.accentGradient)
                HStack {
                    Text(vm.statusText).font(.rounded(12, .medium)).foregroundStyle(.white.opacity(0.7))
                    if vm.producedFile != nil, !vm.converting {
                        Button {
                            vm.revealOutput()
                        } label: {
                            HStack(spacing: 6) { Image(systemName: "folder"); Text(app.tr("Afficher dans le Finder", "Show in Finder")) }
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                    Spacer()
                    Text("\(app.tr("Taille estimée", "Estimated size")) : \(vm.estimatedSize)")
                        .font(.rounded(11)).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private func labeledPicker(_ label: String, selection: Binding<String>, options: [String]) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.rounded(12, .medium)).foregroundStyle(.white.opacity(0.6))
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .accessibilityLabel(label)
        }
    }
}

private struct AdvancedSettingsSheet: View {
    @Bindable var vm: ConversionViewModel
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            HStack(alignment: .top, spacing: 14) {
                if !vm.isAudioOutput {
                    settingsCard(symbol: "video.fill", title: app.tr("Vidéo", "Video")) {
                        settingRow(app.tr("Encodeur", "Encoder"), $vm.settings.videoEncoder, ConversionViewModel.videoEncoders)
                        settingRow("Bitrate", $vm.settings.videoBitrate, ConversionViewModel.videoBitrates)
                        settingRow(app.tr("Cadence", "Frame rate"), $vm.settings.videoFramerate, ConversionViewModel.videoFramerates)
                        settingRow(app.tr("Préréglage", "Preset"), $vm.settings.videoPreset, ConversionViewModel.videoPresets)
                    }
                }
                settingsCard(symbol: "waveform", title: app.tr("Audio", "Audio")) {
                    settingRow(app.tr("Encodeur", "Encoder"), $vm.settings.audioEncoder, ConversionViewModel.audioEncoders)
                    settingRow(app.tr("Canaux", "Channels"), $vm.settings.audioChannels, ConversionViewModel.audioChannelsOptions)
                    settingRow("Bitrate", $vm.settings.audioBitrate, ConversionViewModel.audioBitrates)
                    settingRow(app.tr("Échantillonnage", "Sample rate"), $vm.settings.sampleRate, ConversionViewModel.sampleRates)
                }
            }
            footer
        }
        .padding(26)
        .frame(width: vm.isAudioOutput ? 380 : 640)
        .background(Theme.appBackground)
    }

    private var header: some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.accentGradient)
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white))
                .shadow(color: Theme.accent.opacity(0.4), radius: 8, y: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.tr("Paramètres avancés", "Advanced Settings"))
                    .font(.rounded(19, .bold)).foregroundStyle(.white)
                Text(app.tr("Réglages d'encodage vidéo et audio", "Video and audio encoding settings"))
                    .font(.rounded(12)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            Button { resetAdvanced() } label: {
                HStack(spacing: 6) { Image(systemName: "arrow.counterclockwise"); Text(app.tr("Réinitialiser", "Reset")) }
            }
            .buttonStyle(GhostButtonStyle())
            Spacer()
            Button(app.tr("Terminé", "Done")) { dismiss() }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(symbol: String, title: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(symbol: symbol, title: title)
            VStack(alignment: .leading, spacing: 11) { content() }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    private func settingRow(_ label: String, _ selection: Binding<String>, _ options: [String]) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.rounded(12, .medium)).foregroundStyle(.white.opacity(0.6))
                .frame(width: 92, alignment: .leading)
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .accessibilityLabel(label)
        }
    }

    /// Resets only the encoding fields shown here — leaves output format / quality intact.
    private func resetAdvanced() {
        let d = ConversionSettings()
        withAnimation(.easeOut(duration: 0.15)) {
            vm.settings.videoEncoder = d.videoEncoder
            vm.settings.videoBitrate = d.videoBitrate
            vm.settings.videoFramerate = d.videoFramerate
            vm.settings.videoPreset = d.videoPreset
            vm.settings.audioEncoder = d.audioEncoder
            vm.settings.audioChannels = d.audioChannels
            vm.settings.audioBitrate = d.audioBitrate
            vm.settings.sampleRate = d.sampleRate
        }
    }
}

