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

}
