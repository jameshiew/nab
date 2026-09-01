import AppKit

struct FilePromiseExportFailure {
    let sourceURL: URL
    let errorDescription: String

    init(sourceURL: URL, error: Error) {
        self.sourceURL = sourceURL
        self.errorDescription = error.localizedDescription
    }
}

final class FilePromiseExportCoordinator {
    struct ExportID: Hashable {
        fileprivate let rawValue = UUID()
    }

    private struct ItemState {
        var pendingPromiseIDs: Set<UUID> = []
        var failure: FilePromiseExportFailure?
        var didReportFailure = false
    }

    private struct ExportState {
        var wasAccepted = false
        var items: [ShelfItem.ID: ItemState] = [:]
    }

    private struct PromiseState {
        let exportID: ExportID
        let itemID: ShelfItem.ID
        let sourceURL: URL
        let delegate: MaterializedFilePromiseDelegate
    }

    private var exports: [ExportID: ExportState] = [:]
    private var promises: [UUID: PromiseState] = [:]
    private let onItemsExported: ([ShelfItem.ID]) -> Void
    private let onFailure: (FilePromiseExportFailure) -> Void

    init(
        onItemsExported: @escaping ([ShelfItem.ID]) -> Void,
        onFailure: @escaping (FilePromiseExportFailure) -> Void
    ) {
        self.onItemsExported = onItemsExported
        self.onFailure = onFailure
    }

    func beginExport() -> ExportID {
        let id = ExportID()
        exports[id] = ExportState()
        return id
    }

    func registerItem(_ itemID: ShelfItem.ID, in exportID: ExportID) {
        guard var export = exports[exportID] else { return }
        export.items[itemID] = ItemState()
        exports[exportID] = export
    }

    func makePromiseDelegate(
        sourceURL: URL,
        itemID: ShelfItem.ID,
        in exportID: ExportID
    ) -> MaterializedFilePromiseDelegate {
        guard var export = exports[exportID], var item = export.items[itemID] else {
            preconditionFailure("Register the shelf item before creating its file promises")
        }

        let promiseID = UUID()
        let delegate = MaterializedFilePromiseDelegate(sourceURL: sourceURL) { [weak self] error in
            Task { @MainActor [weak self] in
                self?.promiseDidComplete(promiseID, error: error)
            }
        }
        item.pendingPromiseIDs.insert(promiseID)
        export.items[itemID] = item
        exports[exportID] = export
        promises[promiseID] = PromiseState(
            exportID: exportID,
            itemID: itemID,
            sourceURL: sourceURL,
            delegate: delegate
        )
        return delegate
    }

    func finishExport(_ exportID: ExportID, operation: NSDragOperation) {
        guard DragOperationPolicy.wasAccepted(operation) else {
            cancelExport(exportID)
            return
        }
        guard var export = exports[exportID] else { return }
        export.wasAccepted = true
        exports[exportID] = export
        settleExport(exportID)
    }

    func cancelExport(_ exportID: ExportID) {
        guard let export = exports.removeValue(forKey: exportID) else { return }
        for promiseID in export.items.values.flatMap(\.pendingPromiseIDs) {
            promises.removeValue(forKey: promiseID)
        }
    }

    private func promiseDidComplete(_ promiseID: UUID, error: Error?) {
        guard let promise = promises.removeValue(forKey: promiseID),
            var export = exports[promise.exportID],
            var item = export.items[promise.itemID]
        else { return }

        item.pendingPromiseIDs.remove(promiseID)
        if let error, item.failure == nil {
            item.failure = FilePromiseExportFailure(sourceURL: promise.sourceURL, error: error)
        }
        export.items[promise.itemID] = item
        exports[promise.exportID] = export
        settleExport(promise.exportID)
    }

    private func settleExport(_ exportID: ExportID) {
        guard var export = exports[exportID], export.wasAccepted else { return }
        var exportedItemIDs: [ShelfItem.ID] = []
        var failures: [FilePromiseExportFailure] = []

        for (itemID, var item) in export.items {
            if let failure = item.failure, !item.didReportFailure {
                item.didReportFailure = true
                failures.append(failure)
                export.items[itemID] = item
            }

            guard item.pendingPromiseIDs.isEmpty else { continue }
            if item.failure == nil {
                exportedItemIDs.append(itemID)
            }
            export.items.removeValue(forKey: itemID)
        }

        if export.items.isEmpty {
            exports.removeValue(forKey: exportID)
        } else {
            exports[exportID] = export
        }

        if !exportedItemIDs.isEmpty {
            onItemsExported(exportedItemIDs)
        }
        for failure in failures {
            onFailure(failure)
        }
    }
}

final class MaterializedFilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    let sourceURL: URL
    private let onCompletion: @Sendable (Error?) -> Void
    private static let fileWriteQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "dev.nab.file-promise-write"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    init(sourceURL: URL, onCompletion: @escaping @Sendable (Error?) -> Void) {
        self.sourceURL = sourceURL
        self.onCompletion = onCompletion
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        sourceURL.lastPathComponent
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        Self.fileWriteQueue
    }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let error: Error?
        do {
            try FileManager.default.copyItem(at: sourceURL, to: url)
            error = nil
        } catch let copyError {
            error = copyError
        }
        completionHandler(error)
        onCompletion(error)
    }
}
