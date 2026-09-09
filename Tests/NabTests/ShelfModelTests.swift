import Foundation
import XCTest

@testable import Nab

@MainActor
final class ShelfModelTests: XCTestCase {
    func testAddFiltersDuplicatesWithinDropAndAcrossShelf() throws {
        let originalURL = try makeTemporaryFile(named: "original.txt")
        let aliasURL = originalURL.deletingLastPathComponent()
            .appendingPathComponent("alias.txt")
        try FileManager.default.createSymbolicLink(at: aliasURL, withDestinationURL: originalURL)
        let secondURL = try makeTemporaryFile(named: "second.txt")
        let thirdURL = try makeTemporaryFile(named: "third.txt")
        let model = ShelfModel()

        let firstResult = model.add([originalURL, aliasURL, secondURL])
        let secondResult = model.add([secondURL, thirdURL])

        XCTAssertEqual(firstResult.added, 2)
        XCTAssertEqual(firstResult.duplicates, 1)
        XCTAssertEqual(secondResult.added, 1)
        XCTAssertEqual(secondResult.duplicates, 1)
        XCTAssertEqual(model.items.count, 2)
        XCTAssertEqual(model.items[0].entries.map(\.url), [originalURL, secondURL])
        XCTAssertEqual(model.items[0].displayName, "2 items")
        XCTAssertEqual(model.items[1].primaryURL, thirdURL)
        XCTAssertEqual(model.items[1].displayName, "third.txt")
    }

    func testResolveURLsPrunesMissingEntriesAndRemovesEmptyItem() throws {
        let firstURL = try makeTemporaryFile(named: "first.txt")
        let secondURL = try makeTemporaryFile(named: "second.txt")
        let item = ShelfItem(entries: [FileEntry(url: firstURL), FileEntry(url: secondURL)])
        let model = ShelfModel()
        model.items = [item]
        model.plainClick(item.id)

        try FileManager.default.removeItem(at: firstURL)

        XCTAssertEqual(model.resolveURLs(for: item.id), [secondURL])
        XCTAssertEqual(model.items[0].entries.map(\.url), [secondURL])

        try FileManager.default.removeItem(at: secondURL)

        XCTAssertEqual(model.resolveURLs(for: item.id), [])
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertTrue(model.selectedIDs.isEmpty)
    }

    func testAddRejectsDuplicateAfterParkedFileIsRenamed() throws {
        let originalURL = try makeTemporaryFile(named: "original.txt")
        let renamedURL = originalURL.deletingLastPathComponent()
            .appendingPathComponent("renamed.txt")
        let model = ShelfModel()
        model.add([originalURL])
        XCTAssertNotNil(model.items[0].entries[0].bookmarkData)
        try FileManager.default.moveItem(at: originalURL, to: renamedURL)

        let result = model.add([renamedURL])

        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(result.duplicates, 1)
        XCTAssertEqual(model.items.map(\.primaryURL), [renamedURL])
    }

    func testAddAcceptsReplacementAtRenamedFilesOriginalPath() throws {
        let originalURL = try makeTemporaryFile(named: "original.txt")
        let renamedURL = originalURL.deletingLastPathComponent()
            .appendingPathComponent("renamed.txt")
        let model = ShelfModel()
        model.add([originalURL])
        XCTAssertNotNil(model.items[0].entries[0].bookmarkData)
        try FileManager.default.moveItem(at: originalURL, to: renamedURL)
        try Data("replacement".utf8).write(to: originalURL)

        let result = model.add([originalURL])

        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.duplicates, 0)
        XCTAssertEqual(model.items.map(\.primaryURL), [renamedURL, originalURL])
    }

    func testSplitSelectedStackPreservesOrderAndSelectsEveryReplacement() {
        let entries = ["first.txt", "second.txt", "third.txt"].map {
            FileEntry(url: URL(fileURLWithPath: "/tmp/\($0)"))
        }
        let stack = ShelfItem(entries: entries)
        let trailingItem = ShelfItem(
            entries: [FileEntry(url: URL(fileURLWithPath: "/tmp/trailing.txt"))]
        )
        let model = ShelfModel()
        model.items = [stack, trailingItem]
        model.plainClick(stack.id)

        model.split(stack.id)

        XCTAssertEqual(model.items.map(\.primaryURL), entries.map(\.url) + [trailingItem.primaryURL])
        XCTAssertEqual(model.selectedItemsInOrder().map(\.primaryURL), entries.map(\.url))

        model.extendSelection(to: trailingItem.id)

        XCTAssertEqual(model.selectedIDs, [trailingItem.id])
    }

    func testRangeSelectionUsesAnchorInBothDirections() {
        let items = (0..<4).map {
            ShelfItem(entries: [FileEntry(url: URL(fileURLWithPath: "/tmp/\($0).txt"))])
        }
        let model = ShelfModel()
        model.items = items

        model.extendSelection(to: items[1].id)
        model.extendSelection(to: items[3].id)

        XCTAssertEqual(model.selectedItemsInOrder().map(\.id), Array(items[1...3]).map(\.id))

        model.plainClick(items[2].id)
        model.extendSelection(to: items[0].id)

        XCTAssertEqual(model.selectedItemsInOrder().map(\.id), Array(items[0...2]).map(\.id))
    }

    func testSelectionTogglesAndDragSelectionPreservesOrReplacesSelection() {
        let items = (0..<3).map {
            ShelfItem(entries: [FileEntry(url: URL(fileURLWithPath: "/tmp/\($0).txt"))])
        }
        let model = ShelfModel()
        model.items = items

        model.toggleSelection(items[0].id)
        model.toggleSelection(items[2].id)
        model.ensureSelectedForDrag(items[0].id)

        XCTAssertEqual(model.selectedItemsInOrder().map(\.id), [items[0].id, items[2].id])

        model.toggleSelection(items[0].id)
        model.ensureSelectedForDrag(items[1].id)

        XCTAssertEqual(model.selectedIDs, [items[1].id])

        model.plainClick(items[1].id)

        XCTAssertTrue(model.selectedIDs.isEmpty)
    }

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

    func testLaunchCleanupPreservesRecentMaterializations() throws {
        let store = try makeMaterializedFileStore()
        let materializedURL = try makeMaterializedFile(in: store)

        store.trashAbandonedMaterializations(createdBefore: .distantPast)
        store.waitForPendingOperations()

        XCTAssertTrue(FileManager.default.fileExists(atPath: materializedURL.path))
    }

    func testReadLeaseDefersCleanupUntilFinished() throws {
        let store = try makeMaterializedFileStore()
        let materializedURL = try makeMaterializedFile(in: store)
        let lease = try XCTUnwrap(store.beginReading(materializedURL))

        store.moveToTrash([materializedURL])
        store.waitForPendingOperations()

        XCTAssertTrue(FileManager.default.fileExists(atPath: materializedURL.path))

        lease.finish()
        lease.finish()
        store.waitForPendingOperations()

        XCTAssertFalse(FileManager.default.fileExists(atPath: materializedURL.path))
    }

    func testReadLeaseRejectsFilesOutsideOwnedDirectories() throws {
        let store = try makeMaterializedFileStore()
        let userURL = try makeTemporaryFile(named: "user.txt")

        XCTAssertNil(store.beginReading(userURL))
    }

    func testPromisedFileCleanupPrunesItsEmptyDirectory() throws {
        let store = try makeMaterializedFileStore()
        let directoryURL = try store.createPromisedFileDirectory()
        let promisedFileURL = directoryURL.appendingPathComponent("promised.txt")
        try Data("promised".utf8).write(to: promisedFileURL)

        store.moveToTrash([promisedFileURL])
        store.waitForPendingOperations()

        XCTAssertFalse(FileManager.default.fileExists(atPath: promisedFileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directoryURL.path))
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
