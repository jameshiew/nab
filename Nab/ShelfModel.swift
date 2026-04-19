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
    var selectedIDs: Set<ShelfItem.ID> = []
    private var selectionAnchor: ShelfItem.ID?

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
        selectedIDs.remove(id)
        if selectionAnchor == id { selectionAnchor = nil }
    }

    func remove(ids: [ShelfItem.ID]) {
        let set = Set(ids)
        items.removeAll { set.contains($0.id) }
        selectedIDs.subtract(set)
        if let anchor = selectionAnchor, set.contains(anchor) { selectionAnchor = nil }
    }

    func clear() {
        items.removeAll()
        selectedIDs.removeAll()
        selectionAnchor = nil
    }

    func isSelected(_ id: ShelfItem.ID) -> Bool {
        selectedIDs.contains(id)
    }

    /// Plain click: if the item is the sole current selection, clear it;
    /// otherwise replace the selection with just this item.
    func plainClick(_ id: ShelfItem.ID) {
        if selectedIDs == [id] {
            selectedIDs.removeAll()
            selectionAnchor = nil
        } else {
            selectedIDs = [id]
            selectionAnchor = id
        }
    }

    /// Cmd-click: toggle this item in the selection. The anchor moves here.
    func toggleSelection(_ id: ShelfItem.ID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        selectionAnchor = id
    }

    /// Shift-click: replace selection with the range from the current anchor to `id`.
    /// With no anchor yet, select just `id` and set it as the anchor.
    func extendSelection(to id: ShelfItem.ID) {
        guard let anchor = selectionAnchor,
            let fromIdx = items.firstIndex(where: { $0.id == anchor }),
            let toIdx = items.firstIndex(where: { $0.id == id })
        else {
            selectedIDs = [id]
            selectionAnchor = id
            return
        }
        let range = fromIdx <= toIdx ? fromIdx...toIdx : toIdx...fromIdx
        selectedIDs = Set(items[range].map(\.id))
    }

    /// When a drag starts on `id`: if it isn't already selected, make it the
    /// sole selection so the drag carries a defined payload.
    func ensureSelectedForDrag(_ id: ShelfItem.ID) {
        if !selectedIDs.contains(id) {
            selectedIDs = [id]
            selectionAnchor = id
        }
    }

    /// Selected items in on-screen (items array) order.
    func selectedItemsInOrder() -> [ShelfItem] {
        items.filter { selectedIDs.contains($0.id) }
    }
}
