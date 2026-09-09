import AppKit
import XCTest

@testable import Nab

@MainActor
private final class DragSessionState {
    var isActive = false
}

@MainActor
final class DragMonitorTests: XCTestCase {
    func testMouseDragWithoutActiveDragSessionDoesNothing() {
        let monitor = DragMonitor(isDragSessionActive: { false })
        var started = false
        var movedPoints: [NSPoint] = []
        monitor.dragStarted = { started = true }
        monitor.dragMoved = { movedPoints.append($0) }

        monitor.handleDrag(at: NSPoint(x: 1, y: 1), now: 1)

        XCTAssertFalse(started)
        XCTAssertTrue(movedPoints.isEmpty)
    }

    func testActiveDragSessionStartsOnceAndEndsOnMouseUp() {
        let monitor = DragMonitor(isDragSessionActive: { true })
        var startCount = 0
        var endCount = 0
        var movedPoints: [NSPoint] = []
        monitor.dragStarted = { startCount += 1 }
        monitor.dragEnded = { endCount += 1 }
        monitor.dragMoved = { movedPoints.append($0) }

        monitor.handleDrag(at: NSPoint(x: 10, y: 20), now: 1)
        monitor.handleDrag(at: NSPoint(x: 12, y: 24), now: 1.01)
        monitor.handleMouseUp()

        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(endCount, 1)
        XCTAssertEqual(movedPoints, [NSPoint(x: 10, y: 20), NSPoint(x: 12, y: 24)])
    }

    func testMouseUpAllowsImmediateDetectionAfterRejectedDrag() {
        let state = DragSessionState()
        let monitor = DragMonitor(isDragSessionActive: { state.isActive })
        var startCount = 0
        monitor.dragStarted = { startCount += 1 }

        monitor.handleDrag(at: .zero, now: 1)
        monitor.handleMouseUp()
        state.isActive = true
        monitor.handleDrag(at: .zero, now: 1.01)

        XCTAssertEqual(startCount, 1)
    }
}
