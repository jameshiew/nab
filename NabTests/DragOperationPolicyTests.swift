import AppKit
import XCTest

@testable import Nab

final class DragOperationPolicyTests: XCTestCase {
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
}
