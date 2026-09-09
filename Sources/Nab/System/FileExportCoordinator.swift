import AppKit

final class FileExportCoordinator {
    struct ExportID: Hashable {
        fileprivate let rawValue = UUID()
    }

    private struct ExportState {
        var itemIDs: [ShelfItem.ID] = []
        var readLeases: [MaterializedFileStore.ReadLease] = []
    }

    private var exports: [ExportID: ExportState] = [:]
    private var completedReadLeases: [MaterializedFileStore.ReadLease] = []
    private let materializedFileStore: MaterializedFileStore
    private let onItemsExported: ([ShelfItem.ID]) -> Void

    init(
        materializedFileStore: MaterializedFileStore = .shared,
        onItemsExported: @escaping ([ShelfItem.ID]) -> Void
    ) {
        self.materializedFileStore = materializedFileStore
        self.onItemsExported = onItemsExported
    }

    func beginExport() -> ExportID {
        let id = ExportID()
        exports[id] = ExportState()
        return id
    }

    func registerItem(_ itemID: ShelfItem.ID, in exportID: ExportID) {
        guard var export = exports[exportID] else { return }
        if !export.itemIDs.contains(itemID) {
            export.itemIDs.append(itemID)
        }
        exports[exportID] = export
    }

    func retainMaterializedFile(_ url: URL, in exportID: ExportID) {
        guard var export = exports[exportID],
            let readLease = materializedFileStore.beginReading(url)
        else { return }
        export.readLeases.append(readLease)
        exports[exportID] = export
    }

    func finishExport(_ exportID: ExportID, operation: NSDragOperation) {
        guard DragOperationPolicy.wasAccepted(operation) else {
            cancelExport(exportID)
            return
        }
        guard let export = exports.removeValue(forKey: exportID) else { return }
        withExtendedLifetime(export) {
            onItemsExported(export.itemIDs)
        }
        completedReadLeases.append(contentsOf: export.readLeases)
    }

    func cancelExport(_ exportID: ExportID) {
        exports.removeValue(forKey: exportID)
    }
}
