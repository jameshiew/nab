import Foundation

struct ShelfItem: Identifiable, Hashable {
    let id = UUID()
    var url: URL
    let bookmarkData: Data?

    var displayName: String { url.lastPathComponent }
}

@Observable
final class ShelfModel {
    var items: [ShelfItem] = []

    /// Adds URLs not already on the shelf. Returns how many were added vs. rejected as duplicates.
    @discardableResult
    func add(_ urls: [URL]) -> (added: Int, duplicates: Int) {
        var existing = Set(items.map(\.url.standardizedFileURL))
        var added = 0
        var duplicates = 0
        for url in urls {
            let key = url.standardizedFileURL
            if existing.insert(key).inserted {
                let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                items.append(ShelfItem(url: url, bookmarkData: data))
                added += 1
            } else {
                duplicates += 1
            }
        }
        return (added, duplicates)
    }

    /// Returns the current on-disk URL for the item, updating the cached URL
    /// if the file has moved since being added. Returns nil if the file is gone.
    func resolveURL(for id: ShelfItem.ID) -> URL? {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return nil }
        let item = items[idx]
        if let data = item.bookmarkData {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: data,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), FileManager.default.fileExists(atPath: resolved.path) {
                if resolved != item.url {
                    items[idx].url = resolved
                }
                return resolved
            }
            return nil
        }
        return FileManager.default.fileExists(atPath: item.url.path) ? item.url : nil
    }

    func remove(_ id: ShelfItem.ID) {
        items.removeAll { $0.id == id }
    }

    func clear() {
        items.removeAll()
    }
}
