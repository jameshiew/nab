import AppKit
import CoreGraphics

final class DragMonitor {
    var dragStarted: () -> Void = {}
    var dragEnded: () -> Void = {}
    var dragMoved: (NSPoint) -> Void = { _ in }

    private let isPrimaryButtonPressed: @MainActor () -> Bool
    private let isDragSessionActive: @MainActor () -> Bool
    private let beginActivity: @MainActor () -> NSObjectProtocol
    private let endActivity: @MainActor (NSObjectProtocol) -> Void
    private let recordDiagnostic: @MainActor (String, [String: String]) -> Void
    private var pollTimer: Timer?
    private var monitoringActivity: NSObjectProtocol?
    private var lastPollUptime: TimeInterval?
    private var inDrag = false

    private static let pollInterval: TimeInterval = 0.05

    init(
        isPrimaryButtonPressed: @escaping @MainActor () -> Bool = DragMonitor.primaryButtonIsPressed,
        isDragSessionActive: @escaping @MainActor () -> Bool = DragMonitor.hasActiveDragWindow,
        beginActivity: @escaping @MainActor () -> NSObjectProtocol = {
            ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Monitoring drags to show the file shelf"
            )
        },
        endActivity: @escaping @MainActor (NSObjectProtocol) -> Void = {
            ProcessInfo.processInfo.endActivity($0)
        },
        recordDiagnostic: @escaping @MainActor (String, [String: String]) -> Void = {
            DiagnosticsRecorder.shared.record($0, details: $1)
        }
    ) {
        self.isPrimaryButtonPressed = isPrimaryButtonPressed
        self.isDragSessionActive = isDragSessionActive
        self.beginActivity = beginActivity
        self.endActivity = endActivity
        self.recordDiagnostic = recordDiagnostic
    }

    deinit {
        MainActor.assumeIsolated {
            stop()
        }
    }

    func start() {
        guard pollTimer == nil else { return }
        monitoringActivity = beginActivity()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll(at: NSEvent.mouseLocation)
            }
        }
        timer.tolerance = 0.01
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        recordDiagnostic("drag_monitor_started", [:])
    }

    func stop() {
        let wasMonitoring = pollTimer != nil
        pollTimer?.invalidate()
        pollTimer = nil
        lastPollUptime = nil
        inDrag = false
        if let monitoringActivity {
            endActivity(monitoringActivity)
            self.monitoringActivity = nil
        }
        if wasMonitoring {
            recordDiagnostic("drag_monitor_stopped", [:])
        }
    }

    func endDrag() {
        let wasInDrag = inDrag
        inDrag = false
        if wasInDrag {
            recordDiagnostic("external_drag_ended", [:])
            dragEnded()
        }
    }

    /// A drag session cannot outlive the primary mouse button, so the
    /// comparatively expensive window-list query only runs while it is held.
    func poll(at point: NSPoint, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if let lastPollUptime, uptime - lastPollUptime > 1 {
            recordDiagnostic(
                "drag_monitor_poll_delayed",
                ["elapsed_seconds": String(format: "%.3f", uptime - lastPollUptime)]
            )
        }
        lastPollUptime = uptime

        guard isPrimaryButtonPressed(), isDragSessionActive() else {
            endDrag()
            return
        }

        if !inDrag {
            inDrag = true
            recordDiagnostic(
                "external_drag_started",
                ["cursor_x": String(Double(point.x)), "cursor_y": String(Double(point.y))]
            )
            dragStarted()
        }
        dragMoved(point)
    }

    private static func primaryButtonIsPressed() -> Bool {
        NSEvent.pressedMouseButtons & 1 != 0
    }

    private static func hasActiveDragWindow() -> Bool {
        guard
            let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else { return false }

        return hasActiveDragWindow(in: windows, excludingProcessID: ProcessInfo.processInfo.processIdentifier)
    }

    static func hasActiveDragWindow(in windows: [[String: Any]], excludingProcessID processID: Int32) -> Bool {
        windows.contains {
            ($0[kCGWindowLayer as String] as? Int) == Int(kCGDraggingWindowLevel)
                && ($0[kCGWindowOwnerPID as String] as? Int32) != processID
                && ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0
        }
    }
}
