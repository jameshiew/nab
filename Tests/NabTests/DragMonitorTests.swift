import AppKit
import XCTest

@testable import Nab

@MainActor
private final class DragSessionState {
    var isActive = false
    var isButtonPressed = true
}

@MainActor
final class DragMonitorTests: XCTestCase {
    func testMonitoringKeepsActivityUntilStoppedAndReacquiresItOnRestart() {
        var activities: [NSObject] = []
        var endedActivities: [NSObjectProtocol] = []
        let monitor = DragMonitor(
            beginActivity: {
                let activity = NSObject()
                activities.append(activity)
                return activity
            },
            endActivity: { endedActivities.append($0) },
            recordDiagnostic: { _, _ in }
        )

        monitor.stop()
        XCTAssertTrue(activities.isEmpty)
        XCTAssertTrue(endedActivities.isEmpty)

        monitor.start()
        monitor.start()
        XCTAssertEqual(activities.count, 1)
        XCTAssertTrue(endedActivities.isEmpty)

        monitor.stop()
        monitor.stop()
        XCTAssertEqual(endedActivities.count, 1)
        XCTAssertTrue(endedActivities[0] === activities[0])

        monitor.start()
        XCTAssertEqual(activities.count, 2)
        XCTAssertEqual(endedActivities.count, 1)
        monitor.stop()
        XCTAssertEqual(endedActivities.count, 2)
        XCTAssertTrue(endedActivities[1] === activities[1])
    }

    func testDeinitializingMonitorEndsItsActivity() {
        let activity = NSObject()
        var endedActivities: [NSObjectProtocol] = []
        var monitor: DragMonitor? = DragMonitor(
            beginActivity: { activity },
            endActivity: { endedActivities.append($0) },
            recordDiagnostic: { _, _ in }
        )
        weak let releasedMonitor = monitor

        monitor?.start()
        monitor = nil

        XCTAssertNil(releasedMonitor)
        XCTAssertEqual(endedActivities.count, 1)
        XCTAssertTrue(endedActivities[0] === activity)
    }

    func testDiagnosticsRecordLongPollGapsWithoutLoggingEveryPoll() {
        var events: [(name: String, details: [String: String])] = []
        let monitor = DragMonitor(
            isPrimaryButtonPressed: { false },
            recordDiagnostic: { events.append(($0, $1)) }
        )

        monitor.poll(at: .zero, uptime: 10)
        monitor.poll(at: .zero, uptime: 10.05)
        monitor.poll(at: .zero, uptime: 15.05)
        monitor.poll(at: .zero, uptime: 15.10)

        XCTAssertEqual(events.map(\.name), ["drag_monitor_poll_delayed"])
        XCTAssertEqual(events.first?.details["elapsed_seconds"], "5.000")
    }

    func testRestartDoesNotReportTimeWhileStoppedAsPollingDelay() {
        var events: [String] = []
        let monitor = DragMonitor(
            isPrimaryButtonPressed: { false },
            recordDiagnostic: { name, _ in events.append(name) }
        )

        monitor.start()
        monitor.poll(at: .zero, uptime: 10)
        monitor.stop()
        monitor.start()
        monitor.poll(at: .zero, uptime: 100)
        monitor.stop()

        XCTAssertEqual(
            events,
            ["drag_monitor_started", "drag_monitor_stopped", "drag_monitor_started", "drag_monitor_stopped"]
        )
    }

    func testDiagnosticsRecordDragTransitionsOnce() {
        let state = DragSessionState()
        state.isActive = true
        var events: [(name: String, details: [String: String])] = []
        let monitor = DragMonitor(
            isPrimaryButtonPressed: { state.isButtonPressed },
            isDragSessionActive: { state.isActive },
            recordDiagnostic: { events.append(($0, $1)) }
        )

        monitor.poll(at: NSPoint(x: 10, y: 20), uptime: 10)
        monitor.poll(at: NSPoint(x: 20, y: 30), uptime: 10.05)
        state.isButtonPressed = false
        monitor.poll(at: .zero, uptime: 10.10)
        monitor.poll(at: .zero, uptime: 10.15)

        XCTAssertEqual(events.map(\.name), ["external_drag_started", "external_drag_ended"])
        XCTAssertEqual(events.first?.details, ["cursor_x": "10.0", "cursor_y": "20.0"])
    }

    func testStopResetsManuallyPolledDragAndPollTime() {
        var events: [String] = []
        let monitor = DragMonitor(
            isPrimaryButtonPressed: { true },
            isDragSessionActive: { true },
            recordDiagnostic: { name, _ in events.append(name) }
        )
        var startCount = 0
        var endCount = 0
        monitor.dragStarted = { startCount += 1 }
        monitor.dragEnded = { endCount += 1 }

        monitor.poll(at: .zero, uptime: 10)
        monitor.stop()
        monitor.poll(at: .zero, uptime: 100)

        XCTAssertEqual(startCount, 2)
        XCTAssertEqual(endCount, 0)
        XCTAssertEqual(events, ["external_drag_started", "external_drag_started"])
    }

    func testDetectsDragWithoutMouseEvents() async {
        let monitor = DragMonitor(isPrimaryButtonPressed: { true }, isDragSessionActive: { true })
        let started = expectation(description: "Drag detected without a mouse event")
        monitor.dragStarted = { started.fulfill() }

        monitor.start()
        defer { monitor.stop() }

        await fulfillment(of: [started], timeout: 1)
    }

    func testPollWithoutActiveDragSessionDoesNothing() {
        let monitor = DragMonitor(isPrimaryButtonPressed: { true }, isDragSessionActive: { false })
        var started = false
        var movedPoints: [NSPoint] = []
        monitor.dragStarted = { started = true }
        monitor.dragMoved = { movedPoints.append($0) }

        monitor.poll(at: NSPoint(x: 1, y: 1))

        XCTAssertFalse(started)
        XCTAssertTrue(movedPoints.isEmpty)
    }

    func testSkipsDragWindowCheckWhileNoButtonIsPressed() {
        let state = DragSessionState()
        state.isActive = true
        state.isButtonPressed = false
        var windowChecks = 0
        let monitor = DragMonitor(
            isPrimaryButtonPressed: { state.isButtonPressed },
            isDragSessionActive: {
                windowChecks += 1
                return state.isActive
            }
        )
        var startCount = 0
        monitor.dragStarted = { startCount += 1 }

        monitor.poll(at: .zero)
        monitor.poll(at: .zero)
        XCTAssertEqual(windowChecks, 0)
        XCTAssertEqual(startCount, 0)

        state.isButtonPressed = true
        monitor.poll(at: .zero)

        XCTAssertEqual(windowChecks, 1)
        XCTAssertEqual(startCount, 1)
    }

    func testReleasingButtonEndsDragWhileWindowLingers() {
        let state = DragSessionState()
        state.isActive = true
        let monitor = DragMonitor(
            isPrimaryButtonPressed: { state.isButtonPressed },
            isDragSessionActive: { state.isActive }
        )
        var startCount = 0
        var endCount = 0
        monitor.dragStarted = { startCount += 1 }
        monitor.dragEnded = { endCount += 1 }

        monitor.poll(at: .zero)
        state.isButtonPressed = false
        monitor.poll(at: .zero)
        monitor.poll(at: .zero)

        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(endCount, 1)
    }

    func testActiveDragSessionStartsOnceAndEndsWhenWindowDisappears() {
        let state = DragSessionState()
        state.isActive = true
        let monitor = DragMonitor(
            isPrimaryButtonPressed: { state.isButtonPressed },
            isDragSessionActive: { state.isActive }
        )
        var startCount = 0
        var endCount = 0
        var movedPoints: [NSPoint] = []
        monitor.dragStarted = { startCount += 1 }
        monitor.dragEnded = { endCount += 1 }
        monitor.dragMoved = { movedPoints.append($0) }

        monitor.poll(at: NSPoint(x: 10, y: 20))
        monitor.poll(at: NSPoint(x: 12, y: 24))
        state.isActive = false
        monitor.poll(at: .zero)
        monitor.poll(at: .zero)

        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(endCount, 1)
        XCTAssertEqual(movedPoints, [NSPoint(x: 10, y: 20), NSPoint(x: 12, y: 24)])
    }

    func testDetectsDragWindowThatAppearsAfterInitialPoll() {
        let state = DragSessionState()
        let monitor = DragMonitor(
            isPrimaryButtonPressed: { state.isButtonPressed },
            isDragSessionActive: { state.isActive }
        )
        var startCount = 0
        monitor.dragStarted = { startCount += 1 }

        monitor.poll(at: .zero)
        state.isActive = true
        monitor.poll(at: .zero)

        XCTAssertEqual(startCount, 1)
    }

    func testTimerDetectsSessionEndWithoutMouseUp() async {
        let state = DragSessionState()
        state.isActive = true
        let monitor = DragMonitor(
            isPrimaryButtonPressed: { state.isButtonPressed },
            isDragSessionActive: { state.isActive }
        )
        let ended = expectation(description: "Drag ended without a mouse event")
        monitor.dragStarted = { state.isActive = false }
        monitor.dragEnded = { ended.fulfill() }

        monitor.start()
        defer { monitor.stop() }

        await fulfillment(of: [ended], timeout: 1)
    }

    func testExplicitDragEndNotifiesOnce() {
        let state = DragSessionState()
        state.isActive = true
        let monitor = DragMonitor(
            isPrimaryButtonPressed: { state.isButtonPressed },
            isDragSessionActive: { state.isActive }
        )
        var endCount = 0
        monitor.dragEnded = { endCount += 1 }

        monitor.poll(at: .zero)
        monitor.endDrag()
        state.isActive = false
        monitor.poll(at: .zero)
        monitor.endDrag()

        XCTAssertEqual(endCount, 1)
    }

    func testStopPreventsFurtherPollingAndAllowsRestart() async {
        let monitor = DragMonitor(isPrimaryButtonPressed: { true }, isDragSessionActive: { true })
        let stopped = expectation(description: "Stopped monitor stays idle")
        stopped.isInverted = true
        monitor.dragStarted = { stopped.fulfill() }
        monitor.start()
        monitor.start()
        monitor.stop()

        await fulfillment(of: [stopped], timeout: 0.15)

        let restarted = expectation(description: "Restarted monitor detects drag")
        monitor.dragStarted = { restarted.fulfill() }
        monitor.start()
        defer { monitor.stop() }

        await fulfillment(of: [restarted], timeout: 1)
    }

    func testRecognizesExternalDragWindowWithoutWindowTitle() {
        let window: [String: Any] = [
            kCGWindowLayer as String: NSNumber(value: kCGDraggingWindowLevel),
            kCGWindowOwnerPID as String: NSNumber(value: 42),
        ]

        XCTAssertTrue(DragMonitor.hasActiveDragWindow(in: [window], excludingProcessID: 43))
        XCTAssertFalse(DragMonitor.hasActiveDragWindow(in: [window], excludingProcessID: 42))
    }

    func testIgnoresOrdinaryAndInvisibleWindows() {
        let ordinary: [String: Any] = [
            kCGWindowLayer as String: NSNumber(value: kCGNormalWindowLevel),
            kCGWindowOwnerPID as String: NSNumber(value: 42),
        ]
        let invisible: [String: Any] = [
            kCGWindowLayer as String: NSNumber(value: kCGDraggingWindowLevel),
            kCGWindowOwnerPID as String: NSNumber(value: 42),
            kCGWindowAlpha as String: NSNumber(value: 0),
        ]

        XCTAssertFalse(DragMonitor.hasActiveDragWindow(in: [ordinary, invisible], excludingProcessID: 43))
    }
}
