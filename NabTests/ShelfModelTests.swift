import Foundation
import XCTest

@testable import Nab

@MainActor
final class ShelfModelTests: XCTestCase {
    func testAddPreservesMaterializedOwnership() throws {
        let store = try makeMaterializedFileStore()
        let materializedURL = try makeMaterializedFile(in: store)
        let model = ShelfModel(materializedFileStore: store)

        model.add([FileEntry(url: materializedURL, isMaterializedByNab: true)])

        XCTAssertTrue(model.items[0].entries[0].isMaterializedByNab)
    }

    func testRemoveTrashesMaterializedFileAndPreservesUserFile() throws {
        let store = try makeMaterializedFileStore()
        let materializedURL = try makeMaterializedFile(in: store)
        let userURL = try makeTemporaryFile(named: "user.png")
        let item = ShelfItem(
            entries: [
                FileEntry(url: materializedURL, isMaterializedByNab: true),
                FileEntry(url: userURL),
            ]
        )
        let model = ShelfModel(materializedFileStore: store)
        model.items = [item]

        model.remove(item.id)
        store.waitForPendingOperations()

        XCTAssertFalse(FileManager.default.fileExists(atPath: materializedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: userURL.path))
    }

    func testRemoveIDsTrashesOnlyRemovedMaterializedFiles() throws {
        let store = try makeMaterializedFileStore()
        let removedURL = try makeMaterializedFile(in: store)
        let keptURL = try makeMaterializedFile(in: store)
        let removedItem = ShelfItem(
            entries: [FileEntry(url: removedURL, isMaterializedByNab: true)]
        )
        let keptItem = ShelfItem(
            entries: [FileEntry(url: keptURL, isMaterializedByNab: true)]
        )
        let model = ShelfModel(materializedFileStore: store)
        model.items = [removedItem, keptItem]

        model.remove(ids: [removedItem.id])
        store.waitForPendingOperations()

        XCTAssertFalse(FileManager.default.fileExists(atPath: removedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keptURL.path))
    }

    func testClearTrashesMaterializedFiles() throws {
        let store = try makeMaterializedFileStore()
        let firstURL = try makeMaterializedFile(in: store)
        let secondURL = try makeMaterializedFile(in: store)
        let model = ShelfModel(materializedFileStore: store)
        model.items = [
            ShelfItem(entries: [FileEntry(url: firstURL, isMaterializedByNab: true)]),
            ShelfItem(entries: [FileEntry(url: secondURL, isMaterializedByNab: true)]),
        ]

        model.clear()
        store.waitForPendingOperations()

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.path))
    }

    func testMaterializedFlagCannotDeleteFileOutsideOwnedDirectories() throws {
        let store = try makeMaterializedFileStore()
        let outsideURL = try makeTemporaryFile(named: "outside.png")
        let item = ShelfItem(
            entries: [FileEntry(url: outsideURL, isMaterializedByNab: true)]
        )
        let model = ShelfModel(materializedFileStore: store)
        model.items = [item]

        model.remove(item.id)
        store.waitForPendingOperations()

        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideURL.path))
    }

    func testLaunchCleanupTrashesOnlyRecognizableNabMaterializations() throws {
        let store = try makeMaterializedFileStore()
        let materializedURL = try makeMaterializedFile(in: store)
        let unrelatedURL = materializedURL.deletingLastPathComponent()
            .appendingPathComponent("user-notes.txt")
        try Data().write(to: unrelatedURL)

        store.trashAbandonedMaterializations(
            createdBefore: Date().addingTimeInterval(60)
        )
        store.waitForPendingOperations()

        XCTAssertFalse(FileManager.default.fileExists(atPath: materializedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedURL.path))
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
        let filename = "Screenshot 2026-09-01 at 12.00.00-\(UUID().uuidString).png"
        let url = store.droppedImageURL(filename: filename)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(filename.utf8).write(to: url)
        return url
    }

    private func makeTemporaryFile(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent(name)
        try Data().write(to: url)
        return url
    }
}
