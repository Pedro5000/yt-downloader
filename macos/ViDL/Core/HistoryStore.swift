import Foundation
import Observation

@Observable
@MainActor
final class HistoryStore {
    private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("ViDL", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { entries = []; return }
        entries = (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Adds an entry, de-duplicating by same title-or-url on the same calendar day (mirrors the Python rule).
    func add(_ entry: HistoryEntry) {
        let newDay = entry.downloadDate.split(separator: " ").first.map(String.init) ?? ""
        for existing in entries {
            let day = existing.downloadDate.split(separator: " ").first.map(String.init) ?? ""
            if (existing.title == entry.title || existing.url == entry.url) && day == newDay {
                return
            }
        }
        entries.append(entry)
        save()
    }

    func delete(url: String) {
        entries.removeAll { $0.url == url }
        save()
    }

    func delete(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    /// Re-inserts a previously deleted entry as-is (bypasses add()'s de-duplication).
    func restore(_ entry: HistoryEntry) {
        guard !entries.contains(where: { $0.id == entry.id }) else { return }
        entries.append(entry)
        save()
    }

    /// Filters by query, in stored (insertion) order — the view applies the chosen sort.
    func filtered(_ query: String) -> [HistoryEntry] {
        let q = query.lowercased()
        if q.isEmpty { return entries }
        return entries.filter { $0.title.lowercased().contains(q) || $0.url.lowercased().contains(q) }
    }
}
