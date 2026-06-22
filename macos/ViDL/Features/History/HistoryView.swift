import SwiftUI

enum HistorySort { case recent, oldest, title }

struct HistoryView: View {
    @Environment(AppState.self) private var app
    @Environment(HistoryStore.self) private var history
    @State private var search = ""
    @State private var copiedFeedback = false
    @State private var showClearConfirm = false
    @State private var sortMode: HistorySort = .recent
    @State private var recentlyDeleted: HistoryEntry?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.tr("Historique", "History"))
                            .font(.rounded(28, .bold)).foregroundStyle(.white)
                        Text(app.tr("Vos téléchargements précédents.", "Your previous downloads."))
                            .font(.rounded(13)).foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    if copiedFeedback {
                        Label(app.tr("URL copiée", "URL copied"), systemImage: "checkmark.circle.fill")
                            .font(.rounded(11, .semibold)).foregroundStyle(Theme.success)
                    }
                }
                HStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.4))
                        TextField(app.tr("Rechercher…", "Search…"), text: $search)
                            .textFieldStyle(.plain).font(.rounded(13)).foregroundStyle(.white)
                            .focused($searchFocused)
                    }
                    .fieldBackground(focused: searchFocused)

                    Picker("", selection: $sortMode) {
                        Text(app.tr("Récents", "Recent")).tag(HistorySort.recent)
                        Text(app.tr("Anciens", "Oldest")).tag(HistorySort.oldest)
                        Text(app.tr("Titre", "Title")).tag(HistorySort.title)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .tint(.white.opacity(0.7))
                    .accessibilityLabel(app.tr("Trier", "Sort"))
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 16)

            let items = sorted(history.filtered(search))
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(items) { entry in
                            row(entry)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 20)
                }
                .scrollContentBackground(.hidden)
            }

            if let deleted = recentlyDeleted {
                HStack(spacing: 10) {
                    Image(systemName: "trash").foregroundStyle(.white.opacity(0.6))
                    Text(app.tr("« \(deleted.title) » supprimé", "“\(deleted.title)” deleted"))
                        .font(.rounded(12, .medium)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    Spacer()
                    Button(app.tr("Annuler", "Undo")) { undoDelete() }
                        .buttonStyle(GhostButtonStyle(tint: Theme.accent))
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if !history.entries.isEmpty {
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        HStack(spacing: 6) { Image(systemName: "trash"); Text(app.tr("Effacer l'historique", "Clear History")) }
                    }
                    .buttonStyle(GhostButtonStyle(tint: Theme.danger))
                    Spacer()
                }
                .padding(.vertical, 14)
            }
        }
        .confirmationDialog(app.tr("Effacer tout l'historique ?", "Clear the entire history?"),
                            isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button(app.tr("Effacer", "Clear"), role: .destructive) { history.clear() }
            Button(app.tr("Annuler", "Cancel"), role: .cancel) {}
        }
    }

    private func sorted(_ items: [HistoryEntry]) -> [HistoryEntry] {
        switch sortMode {
        case .recent: return items.sorted { $0.downloadDate > $1.downloadDate }
        case .oldest: return items.sorted { $0.downloadDate < $1.downloadDate }
        case .title:  return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    private func delete(_ entry: HistoryEntry) {
        history.delete(entry)
        withAnimation { recentlyDeleted = entry }
        let id = entry.id
        Task {
            try? await Task.sleep(for: .seconds(6))
            if recentlyDeleted?.id == id { withAnimation { recentlyDeleted = nil } }
        }
    }

    private func undoDelete() {
        guard let entry = recentlyDeleted else { return }
        history.restore(entry)
        withAnimation { recentlyDeleted = nil }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 44)).foregroundStyle(.white.opacity(0.25))
            Text(app.tr("Aucun téléchargement pour l'instant.", "No downloads yet."))
                .font(.rounded(14, .medium)).foregroundStyle(.white.opacity(0.4))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ entry: HistoryEntry) -> some View {
        GlassCard(padding: 12) {
            HStack(spacing: 14) {
                RemoteThumbnail(urlString: entry.thumbnailURL, width: 96, height: 54, cornerRadius: 8)
                    .draggableFile(entry.filePath)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title).font(.rounded(14, .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(entry.url).font(.rounded(11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1).truncationMode(.middle)
                    Text(entry.downloadDate).font(.rounded(10)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Button {
                    app.openInDownload(entry.url)
                } label: { Image(systemName: "arrow.down.circle") }
                    .buttonStyle(IconButtonStyle())
                    .help(app.tr("Télécharger à nouveau", "Download again"))
                    .accessibilityLabel(app.tr("Réutiliser cette URL pour télécharger", "Reuse this URL to download"))
                if let path = entry.filePath, FileManager.default.fileExists(atPath: path) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    } label: { Image(systemName: "folder") }
                        .buttonStyle(IconButtonStyle())
                        .help(app.tr("Afficher dans le Finder", "Show in Finder"))
                        .accessibilityLabel(app.tr("Afficher le fichier dans le Finder", "Show file in Finder"))
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.url, forType: .string)
                    withAnimation { copiedFeedback = true }
                    Task { try? await Task.sleep(for: .seconds(2)); withAnimation { copiedFeedback = false } }
                } label: { Image(systemName: "doc.on.clipboard") }
                    .buttonStyle(IconButtonStyle())
                    .help(app.tr("Copier l'URL", "Copy URL"))
                    .accessibilityLabel(app.tr("Copier l'URL", "Copy URL"))
                Button {
                    delete(entry)
                } label: { Image(systemName: "trash") }
                    .buttonStyle(IconButtonStyle())
                    .help(app.tr("Supprimer", "Delete"))
                    .accessibilityLabel(app.tr("Supprimer de l'historique", "Delete from history"))
            }
        }
    }
}
