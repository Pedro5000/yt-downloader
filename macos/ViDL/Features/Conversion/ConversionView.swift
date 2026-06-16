import SwiftUI

struct ConversionView: View {
    @Environment(AppState.self) private var app
    @Bindable var vm: ConversionViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if vm.hasMissingFFmpeg {
                    WarningBanner(title: app.tr("ffmpeg est introuvable. Installez-le pour convertir :",
                                                "ffmpeg not found. Install it to convert:"),
                                  command: "brew install ffmpeg")
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
            guard let file = urls.first(where: { $0.isFileURL }) else { return false }
            Task { await vm.loadFile(path: file.path) }
            return true
        }
        .onAppear { vm.app = app }
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
                        InfoRow(label: app.tr("Débit", "Bit rate"), value: info.formatBitRate)
                        InfoRow(label: "Codec", value: "\(info.videoCodec) / \(info.audioCodec)")
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
                HStack(spacing: 24) {
                    labeledPicker(app.tr("Format", "Format"), selection: $vm.settings.outputFormat, options: ConversionViewModel.outputFormats)
                    labeledPicker(app.tr("Qualité", "Quality"), selection: $vm.settings.quality, options: ConversionViewModel.qualities)
                }
                HStack(spacing: 24) {
                    labeledPicker(app.tr("Résolution", "Resolution"), selection: $vm.settings.resolution, options: ConversionViewModel.resolutions)
                    labeledPicker(app.tr("Échantillonnage", "Sample rate"), selection: $vm.settings.sampleRate, options: ConversionViewModel.sampleRates)
                }
                HStack {
                    Button {
                        vm.showAdvanced = true
                    } label: {
                        HStack(spacing: 6) { Image(systemName: "gearshape.2"); Text(app.tr("Paramètres avancés", "Advanced Settings")) }
                    }
                    .buttonStyle(GhostButtonStyle())
                    Spacer()
                    Toggle(app.tr("Optimiser pour le streaming", "Optimize for streaming"), isOn: $vm.settings.optimizeStreaming)
                        .toggleStyle(.switch).font(.rounded(12)).foregroundStyle(.white.opacity(0.7))
                }
                HStack(spacing: 12) {
                    if vm.converting {
                        Button { vm.cancelConversion() } label: {
                            HStack(spacing: 6) { Image(systemName: "xmark"); Text(app.tr("Annuler", "Cancel")) }
                        }
                        .buttonStyle(GhostButtonStyle(tint: Theme.danger))
                    }
                    Spacer()
                    Button {
                        Task { await vm.startConversion() }
                    } label: {
                        HStack(spacing: 7) { Image(systemName: "wand.and.stars"); Text(app.tr("Démarrer la conversion", "Start Conversion")) }
                    }
                    .buttonStyle(AccentButtonStyle(gradient: Theme.successGradient))
                    .disabled(vm.converting)
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
                    Spacer()
                    Text("\(app.tr("Taille estimée", "Estimated size")) : \(vm.estimatedSize)")
                        .font(.rounded(11)).foregroundStyle(.white.opacity(0.45))
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
        }
    }
}

private struct AdvancedSettingsSheet: View {
    @Bindable var vm: ConversionViewModel
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(app.tr("Paramètres avancés", "Advanced Settings"))
                .font(.rounded(20, .bold)).foregroundStyle(.white)
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(symbol: "video", title: app.tr("Vidéo", "Video"))
                    row(app.tr("Encodeur", "Encoder"), $vm.settings.videoEncoder, ConversionViewModel.videoEncoders)
                    row("Bitrate", $vm.settings.videoBitrate, ConversionViewModel.videoBitrates)
                    row(app.tr("Cadence", "Frame rate"), $vm.settings.videoFramerate, ConversionViewModel.videoFramerates)
                    row(app.tr("Préréglage", "Preset"), $vm.settings.videoPreset, ConversionViewModel.videoPresets)
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(symbol: "waveform", title: app.tr("Audio", "Audio"))
                    row(app.tr("Encodeur", "Encoder"), $vm.settings.audioEncoder, ConversionViewModel.audioEncoders)
                    row(app.tr("Canaux", "Channels"), $vm.settings.audioChannels, ConversionViewModel.audioChannelsOptions)
                    row("Bitrate", $vm.settings.audioBitrate, ConversionViewModel.audioBitrates)
                    row(app.tr("Échantillonnage", "Sample rate"), $vm.settings.sampleRate, ConversionViewModel.sampleRates)
                }
            }
            HStack {
                Spacer()
                Button("OK") { dismiss() }.buttonStyle(AccentButtonStyle())
            }
        }
        .padding(28)
        .frame(width: 560)
        .background(Theme.appBackground)
    }

    private func row(_ label: String, _ selection: Binding<String>, _ options: [String]) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.rounded(12, .medium)).foregroundStyle(.white.opacity(0.6)).frame(width: 110, alignment: .leading)
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().frame(width: 150)
        }
    }
}
