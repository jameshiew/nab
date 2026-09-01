import AppKit
import XCTest

@testable import Nab

final class DragOperationPolicyTests: XCTestCase {
    func testMaterializedFilesCanOnlyBeCopiedWithinApplication() {
        XCTAssertEqual(
            DragOperationPolicy.sourceMask(
                for: .withinApplication,
                containsMaterializedFiles: true
            ),
            .copy
        )
    }

    func testMaterializedFilesCanOnlyBeCopiedOutsideApplication() {
        XCTAssertEqual(
            DragOperationPolicy.sourceMask(
                for: .outsideApplication,
                containsMaterializedFiles: true
            ),
            .copy
        )
    }

    func testUserFilesCanOnlyBeMovedWithinApplication() {
        XCTAssertEqual(
            DragOperationPolicy.sourceMask(
                for: .withinApplication,
                containsMaterializedFiles: false
            ),
            .move
        )
    }

    func testUserFilesCanOnlyBeCopiedOutsideApplication() {
        XCTAssertEqual(
            DragOperationPolicy.sourceMask(
                for: .outsideApplication,
                containsMaterializedFiles: false
            ),
            .copy
        )
    }

    func testMoveIsAccepted() {
        XCTAssertTrue(DragOperationPolicy.wasAccepted(.move))
    }

    func testCombinedOperationIsAccepted() {
        XCTAssertTrue(DragOperationPolicy.wasAccepted([.copy, .move]))
    }

    func testCopyIsAccepted() {
        XCTAssertTrue(DragOperationPolicy.wasAccepted(.copy))
    }

    func testEmptyOperationIsNotAccepted() {
        XCTAssertFalse(DragOperationPolicy.wasAccepted([]))
    }

    @MainActor
    func testMaterializedFilePromiseCopiesToDestination() async throws {
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

        let providerCompletion = expectation(description: "provider completion")
        let delegateCompletion = expectation(description: "delegate completion")
        let delegate = MaterializedFilePromiseDelegate(sourceURL: sourceURL) { _ in
            delegateCompletion.fulfill()
        }
        let provider = NSFilePromiseProvider(fileType: "public.png", delegate: delegate)
        var copyError: Error?
        delegate.filePromiseProvider(provider, writePromiseTo: destinationURL) {
            copyError = $0
            providerCompletion.fulfill()
        }
        await fulfillment(
            of: [providerCompletion, delegateCompletion],
            timeout: 1,
            enforceOrder: true
        )

        XCTAssertNil(copyError)
        XCTAssertEqual(try Data(contentsOf: destinationURL), contents)
        XCTAssertEqual(
            delegate.filePromiseProvider(provider, fileNameForType: "public.png"),
            sourceURL.lastPathComponent
        )
    }
}
