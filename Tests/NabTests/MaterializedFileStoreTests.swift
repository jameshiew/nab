import Foundation
import XCTest

@testable import Nab

final class MaterializedFileStoreTests: XCTestCase {
    func testChildReadLeaseDefersAbandonedDirectoryCleanup() throws {
        let store = try makeStore()
        let directoryURL = try store.createPromisedFileDirectory()
        let fileURL = directoryURL.appendingPathComponent("promised.txt")
        try Data("promised".utf8).write(to: fileURL)
        let lease = try XCTUnwrap(store.beginReading(fileURL))

        store.trashAbandonedMaterializations(createdBefore: .distantFuture)
        store.waitForPendingOperations()

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        lease.finish()
        store.waitForPendingOperations()

        XCTAssertFalse(FileManager.default.fileExists(atPath: directoryURL.path))
    }

    func testDirectoryReadLeaseDefersChildCleanup() throws {
        let store = try makeStore()
        let directoryURL = try store.createPromisedFileDirectory()
        let fileURL = directoryURL.appendingPathComponent("promised.txt")
        try Data("promised".utf8).write(to: fileURL)
        let lease = try XCTUnwrap(store.beginReading(directoryURL))

        store.moveToTrash([fileURL])
        store.waitForPendingOperations()

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        lease.finish()
        store.waitForPendingOperations()

        XCTAssertFalse(FileManager.default.fileExists(atPath: directoryURL.path))
    }

    func testDirectoryCleanupWaitsForEveryOverlappingReadLease() throws {
        let store = try makeStore()
        let directoryURL = try store.createPromisedFileDirectory()
        let fileURL = directoryURL.appendingPathComponent("promised.txt")
        try Data("promised".utf8).write(to: fileURL)
        let firstLease = try XCTUnwrap(store.beginReading(fileURL))
        let secondLease = try XCTUnwrap(store.beginReading(fileURL))
        let directoryLease = try XCTUnwrap(store.beginReading(directoryURL))

        store.moveToTrash([directoryURL])
        firstLease.finish()
        directoryLease.finish()
        store.waitForPendingOperations()

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        secondLease.finish()
        secondLease.finish()
        store.waitForPendingOperations()

        XCTAssertFalse(FileManager.default.fileExists(atPath: directoryURL.path))
    }

    func testReadLeaseDoesNotBlockSiblingCleanup() throws {
        let store = try makeStore()
        let directoryURL = try store.createPromisedFileDirectory()
        let fileURL = directoryURL.appendingPathComponent("promised")
        let siblingURL = directoryURL.appendingPathComponent("promised-copy")
        try Data("promised".utf8).write(to: fileURL)
        try Data("sibling".utf8).write(to: siblingURL)
        let lease = try XCTUnwrap(store.beginReading(fileURL))
        defer { lease.finish() }

        store.moveToTrash([siblingURL])
        store.waitForPendingOperations()

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: siblingURL.path))
    }

    func testReadLeaseRejectsRemovedMaterialization() throws {
        let store = try makeStore()
        let directoryURL = try store.createPromisedFileDirectory()

        store.moveToTrash([directoryURL])
        store.waitForPendingOperations()

        XCTAssertNil(store.beginReading(directoryURL))
    }

    func testCleanupDoesNotPruneDirectoryContainingMovedFileReadLease() throws {
        let store = try makeStore()
        let directoryURL = try store.createPromisedFileDirectory()
        let fileURL = directoryURL.appendingPathComponent("promised.txt")
        let siblingURL = directoryURL.appendingPathComponent("sibling.txt")
        try Data("promised".utf8).write(to: fileURL)
        try Data("sibling".utf8).write(to: siblingURL)
        let lease = try XCTUnwrap(store.beginReading(siblingURL))
        let destinationURL = try store.createPromisedFileDirectory()
            .appendingPathComponent("moved.txt")
        try FileManager.default.moveItem(at: siblingURL, to: destinationURL)

        store.moveToTrash([fileURL])
        store.waitForPendingOperations()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))

        lease.finish()
        store.trashAbandonedMaterializations(createdBefore: .distantFuture)
        store.waitForPendingOperations()

        XCTAssertFalse(FileManager.default.fileExists(atPath: directoryURL.path))
    }

    private func makeStore() throws -> MaterializedFileStore {
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
}
