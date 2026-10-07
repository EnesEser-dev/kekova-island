import AppKit
import Foundation

struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let bookmark: Data
}

/// Files parked on the island. Only bookmarks are kept, never copies, so the shelf
/// survives restarts and follows files that get renamed or moved.
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    private static let defaultsKey = "shelfBookmarks"
    private let defaults = UserDefaults.standard

    init() {
        load()
    }

    func add(_ urls: [URL]) {
        let existing = Set(items.map(\.url.standardizedFileURL))
        let newItems = urls
            .filter { !existing.contains($0.standardizedFileURL) }
            .compactMap { url -> ShelfItem? in
                guard let bookmark = try? url.bookmarkData() else { return nil }
                return ShelfItem(id: UUID(), url: url, bookmark: bookmark)
            }
        guard !newItems.isEmpty else { return }
        items.append(contentsOf: newItems)
        save()
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func removeAll() {
        items.removeAll()
        save()
    }

    /// Re-resolves bookmarks so moved files keep working and deleted ones disappear.
    func refresh() {
        let resolved = items.compactMap(Self.resolve)
        guard resolved != items else { return }
        items = resolved
        save()
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    private func load() {
        let bookmarks = defaults.array(forKey: Self.defaultsKey) as? [Data] ?? []
        items = bookmarks.compactMap { Self.resolve(ShelfItem(id: UUID(), url: URL(fileURLWithPath: "/"), bookmark: $0)) }
    }

    private func save() {
        defaults.set(items.map(\.bookmark), forKey: Self.defaultsKey)
    }

    private static func resolve(_ item: ShelfItem) -> ShelfItem? {
        var isStale = false
        guard
            let url = try? URL(resolvingBookmarkData: item.bookmark, bookmarkDataIsStale: &isStale),
            FileManager.default.fileExists(atPath: url.path),
            // A moved-to-Trash file still resolves; treat it as gone.
            !url.pathComponents.contains(".Trash")
        else { return nil }
        let bookmark = isStale ? (try? url.bookmarkData()) ?? item.bookmark : item.bookmark
        return ShelfItem(id: item.id, url: url, bookmark: bookmark)
    }
}
