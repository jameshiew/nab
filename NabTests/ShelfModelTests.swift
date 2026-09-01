import Foundation
import XCTest

@testable import Nab

@MainActor
final class ShelfModelTests: XCTestCase {
    func testAddPreservesMaterializedOwnership() throws {
        let materializedURL = try makeTemporaryFile(named: "materialized.png")
        let model = ShelfModel()

        model.add([FileEntry(url: materializedURL, isMaterializedByNab: true)])

        XCTAssertTrue(model.items[0].entries[0].isMaterializedByNab)
    }

    func testRemoveDeletesOnlyMaterializedFiles() throws {
        let materializedURL = try makeTemporaryFile(named: "materialized.png")
        let userURL = try makeTemporaryFile(named: "user.png")
        let item = ShelfItem(
            entries: [
                FileEntry(url: materializedURL, isMaterializedByNab: true),
                FileEntry(url: userURL),
            ]
        )
        let model = ShelfModel()
        model.items = [item]

        model.remove(item.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: materializedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: userURL.path))
    }

    func testRemoveIDsDeletesOnlyFilesForRemovedItems() throws {
        let removedURL = try makeTemporaryFile(named: "removed.png")
        let keptURL = try makeTemporaryFile(named: "kept.png")
        let removedItem = ShelfItem(
            entries: [FileEntry(url: removedURL, isMaterializedByNab: true)]
        )
        let keptItem = ShelfItem(
            entries: [FileEntry(url: keptURL, isMaterializedByNab: true)]
        )
        let model = ShelfModel()
        model.items = [removedItem, keptItem]

        model.remove(ids: [removedItem.id])

        XCTAssertFalse(FileManager.default.fileExists(atPath: removedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keptURL.path))
    }

    func testClearDeletesAllMaterializedFiles() throws {
        let firstURL = try makeTemporaryFile(named: "first.png")
        let secondURL = try makeTemporaryFile(named: "second.png")
        let model = ShelfModel()
        model.items = [
            ShelfItem(entries: [FileEntry(url: firstURL, isMaterializedByNab: true)]),
            ShelfItem(entries: [FileEntry(url: secondURL, isMaterializedByNab: true)]),
        ]

        model.clear()

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.path))
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
