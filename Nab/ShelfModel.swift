import Foundation

struct ShelfItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL

    var displayName: String { url.lastPathComponent }
}

@Observable
final class ShelfModel {
    var items: [ShelfItem] = []

    func add(_ urls: [URL]) {
        let new = urls.map { ShelfItem(url: $0) }
        items.append(contentsOf: new)
    }

    func remove(_ id: ShelfItem.ID) {
        items.removeAll { $0.id == id }
    }

    func clear() {
        items.removeAll()
    }
}
