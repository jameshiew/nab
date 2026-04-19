import Foundation

struct ShelfItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL

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
                items.append(ShelfItem(url: url))
                added += 1
            } else {
                duplicates += 1
            }
        }
        return (added, duplicates)
    }

    func remove(_ id: ShelfItem.ID) {
        items.removeAll { $0.id == id }
    }

    func clear() {
        items.removeAll()
    }
}
