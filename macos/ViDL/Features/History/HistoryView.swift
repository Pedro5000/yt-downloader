import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var app
    @Environment(HistoryStore.self) private var history
    @State private var search = ""
    @State private var copiedFeedback = false
    @State private var showClearConfirm = false

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
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.4))
                    TextField(app.tr("Rechercher…", "Search…"), text: $search)
                        .textFieldStyle(.plain).font(.rounded(13)).foregroundStyle(.white)
                }
                .fieldBackground()
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 16)

            let items = history.filtered(search)
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
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title).font(.rounded(14, .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(entry.url).font(.rounded(11)).foregroundStyle(.white.opacity(0.4)).lineLimit(1).truncationMode(.middle)
                    Text(entry.downloadDate).font(.rounded(10)).foregroundStyle(.white.opacity(0.3))
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.url, forType: .string)
                    withAnimation { copiedFeedback = true }
                    Task { try? await Task.sleep(for: .seconds(2)); withAnimation { copiedFeedback = false } }
                } label: { Image(systemName: "doc.on.clipboard") }
                    .buttonStyle(IconButtonStyle())
                    .help(app.tr("Copier l'URL", "Copy URL"))
                Button {
                    history.delete(entry)
                } label: { Image(systemName: "trash") }
                    .buttonStyle(IconButtonStyle())
                    .help(app.tr("Supprimer", "Delete"))
            }
        }
    }
}
