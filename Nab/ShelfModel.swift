import Foundation

struct FileEntry: Hashable {
    var url: URL
    let bookmarkData: Data?
}

struct ShelfItem: Identifiable, Hashable {
    let id = UUID()
    var entries: [FileEntry]

    var isStack: Bool { entries.count > 1 }
    var primaryURL: URL { entries[0].url }
    var urls: [URL] { entries.map(\.url) }
    var displayName: String {
        isStack ? "\(entries.count) items" : entries[0].url.lastPathComponent
    }
}

@Observable
final class ShelfModel {
    var items: [ShelfItem] = []
    var selectedIDs: Set<ShelfItem.ID> = []
    private var selectionAnchor: ShelfItem.ID?

    /// Adds URLs as a single shelf item — a stack if more than one remains after
    /// filtering out files already on the shelf. Returns how many files were
    /// added vs. rejected as duplicates.
    @discardableResult
    func add(_ urls: [URL]) -> (added: Int, duplicates: Int) {
        var existing = Set(items.flatMap { $0.entries.map(\.url.standardizedFileURL) })
        var entries: [FileEntry] = []
        var duplicates = 0
        for url in urls {
            let key = url.standardizedFileURL
            if existing.insert(key).inserted {
                let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                entries.append(FileEntry(url: url, bookmarkData: data))
            } else {
                duplicates += 1
            }
        }
        if !entries.isEmpty {
            items.append(ShelfItem(entries: entries))
        }
        return (entries.count, duplicates)
    }

    /// Returns the current on-disk URLs for the item, refreshing cached URLs via
    /// bookmarks and pruning files that have gone missing. If every file is
    /// gone, the shelf item itself is removed and an empty array is returned.
    func resolveURLs(for id: ShelfItem.ID) -> [URL] {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return [] }
        var resolved: [URL] = []
        var keptEntries: [FileEntry] = []
        for entry in items[idx].entries {
            if let data = entry.bookmarkData {
                var isStale = false
                if let url = try? URL(
                    resolvingBookmarkData: data,
                    options: [.withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ), FileManager.default.fileExists(atPath: url.path) {
                    var updated = entry
                    updated.url = url
                    keptEntries.append(updated)
                    resolved.append(url)
                    continue
                }
            } else if FileManager.default.fileExists(atPath: entry.url.path) {
                keptEntries.append(entry)
                resolved.append(entry.url)
                continue
            }
            // File is gone and can't be recovered — drop this entry.
        }
        if keptEntries.isEmpty {
            remove(id)
        } else if keptEntries != items[idx].entries {
            items[idx].entries = keptEntries
        }
        return resolved
    }

    /// Replaces the stack with one separate shelf item per entry, preserving
    /// ordering and extending the selection to cover all the new items.
    func split(_ id: ShelfItem.ID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let entries = items[idx].entries
        guard entries.count > 1 else { return }
        let replacements = entries.map { ShelfItem(entries: [$0]) }
        items.replaceSubrange(idx...idx, with: replacements)
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
            selectedIDs.formUnion(replacements.map(\.id))
        }
        if selectionAnchor == id { selectionAnchor = nil }
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
