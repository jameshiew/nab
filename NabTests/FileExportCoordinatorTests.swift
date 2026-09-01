import AppKit
import Foundation
import XCTest

@testable import Nab

@MainActor
final class FileExportCoordinatorTests: XCTestCase {
    func testAcceptedExportRetainsMaterializedFileForCoordinatorLifetime() throws {
        let store = try makeMaterializedFileStore()
        let source = try makeMaterializedFile(in: store)
        let item = ShelfItem(entries: [FileEntry(url: source, isMaterializedByNab: true)])
        let model = ShelfModel(materializedFileStore: store)
        model.items = [item]
        var existedDuringRemoval = false
        var coordinator: FileExportCoordinator? = FileExportCoordinator(
            materializedFileStore: store,
            onItemsExported: { itemIDs in
                model.remove(ids: itemIDs)
                store.waitForPendingOperations()
                existedDuringRemoval = FileManager.default.fileExists(atPath: source.path)
            }
        )

        let exportID = coordinator!.beginExport()
        coordinator!.registerItem(item.id, in: exportID)
        coordinator!.retainMaterializedFile(source, in: exportID)
        coordinator!.finishExport(exportID, operation: .copy)
        store.waitForPendingOperations()

        XCTAssertTrue(existedDuringRemoval)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))

        coordinator = nil
        store.waitForPendingOperations()

        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testCancelledExportKeepsItem() throws {
        let store = try makeMaterializedFileStore()
        let source = try makeMaterializedFile(in: store)
        let itemID = UUID()
        var exportedItemIDs: [[ShelfItem.ID]] = []
        let coordinator = FileExportCoordinator(
            materializedFileStore: store,
            onItemsExported: { exportedItemIDs.append($0) }
        )

        let exportID = coordinator.beginExport()
        coordinator.registerItem(itemID, in: exportID)
        coordinator.retainMaterializedFile(source, in: exportID)
        coordinator.finishExport(exportID, operation: [])

        XCTAssertTrue(exportedItemIDs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testCancelReleasesMaterializedFileLease() throws {
        let store = try makeMaterializedFileStore()
        let source = try makeMaterializedFile(in: store)
        let coordinator = FileExportCoordinator(
            materializedFileStore: store,
            onItemsExported: { _ in XCTFail("Unexpected export") }
        )

        let exportID = coordinator.beginExport()
        coordinator.retainMaterializedFile(source, in: exportID)
        store.moveToTrash([source])
        store.waitForPendingOperations()
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))

        coordinator.cancelExport(exportID)
        store.waitForPendingOperations()

        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testAcceptedExportPreservesRegistrationOrderWithoutDuplicates() {
        let firstItemID = UUID()
        let secondItemID = UUID()
        var exportedItemIDs: [[ShelfItem.ID]] = []
        let coordinator = FileExportCoordinator {
            exportedItemIDs.append($0)
        }

        let exportID = coordinator.beginExport()
        coordinator.registerItem(firstItemID, in: exportID)
        coordinator.registerItem(secondItemID, in: exportID)
        coordinator.registerItem(firstItemID, in: exportID)
        coordinator.finishExport(exportID, operation: .copy)

        XCTAssertEqual(exportedItemIDs, [[firstItemID, secondItemID]])
    }

    private func makeMaterializedFileStore() throws -> MaterializedFileStore {
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: applicationSupportURL)
        }
        return MaterializedFileStore(
            applicationSupportURL: applicationSupportURL,
            trashItem: { url in try FileManager.default.removeItem(at: url) }
        )
    }

    private func makeMaterializedFile(in store: MaterializedFileStore) throws -> URL {
        let filename = "Screenshot 2026-09-02 at 12.00.00-\(UUID().uuidString).png"
        let url = store.droppedImageURL(filename: filename)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("source".utf8).write(to: url)
        return url
    }
}
