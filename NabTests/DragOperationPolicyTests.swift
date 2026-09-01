import AppKit
import XCTest

@testable import Nab

final class DragOperationPolicyTests: XCTestCase {
    func testMaterializedFilesCanOnlyBeCopied() {
        XCTAssertEqual(DragOperationPolicy.sourceMask(containsMaterializedFiles: true), .copy)
    }

    func testUserFilesCanBeMovedOrCopied() {
        XCTAssertEqual(
            DragOperationPolicy.sourceMask(containsMaterializedFiles: false),
            [.move, .copy]
        )
    }

    func testMoveRemovesDraggedItems() {
        XCTAssertTrue(DragOperationPolicy.shouldRemoveItems(after: .move))
    }

    func testOperationContainingMoveRemovesDraggedItems() {
        XCTAssertTrue(DragOperationPolicy.shouldRemoveItems(after: [.copy, .move]))
    }

    func testCopyKeepsDraggedItems() {
        XCTAssertFalse(DragOperationPolicy.shouldRemoveItems(after: .copy))
    }

    func testCancelledOrRejectedDragKeepsDraggedItems() {
        XCTAssertFalse(DragOperationPolicy.shouldRemoveItems(after: []))
    }

    @MainActor
    func testMaterializedFilePromiseCopiesToDestination() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let sourceURL = directory.appendingPathComponent("source.png")
        let destinationURL = directory.appendingPathComponent("destination.png")
        let contents = Data("image data".utf8)
        try contents.write(to: sourceURL)

        let delegate = MaterializedFilePromiseDelegate(sourceURL: sourceURL)
        let provider = NSFilePromiseProvider(fileType: "public.png", delegate: delegate)
        var copyError: Error?
        delegate.filePromiseProvider(provider, writePromiseTo: destinationURL) {
            copyError = $0
        }

        XCTAssertNil(copyError)
        XCTAssertEqual(try Data(contentsOf: destinationURL), contents)
        XCTAssertEqual(
            delegate.filePromiseProvider(provider, fileNameForType: "public.png"),
            sourceURL.lastPathComponent
        )
    }
}
