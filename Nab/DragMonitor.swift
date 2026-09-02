import AppKit
import CoreGraphics

/// Watches for system-wide drag-and-drop sessions.
/// Posts `dragStarted` once per drag, then `dragEnded` on mouse up.
final class DragMonitor {
    var dragStarted: () -> Void = {}
    var dragEnded: () -> Void = {}
    var dragMoved: (NSPoint) -> Void = { _ in }

    private let isDragSessionActive: @MainActor () -> Bool
    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var inDrag = false
    private var lastPoll: TimeInterval = 0

    private static let pollInterval: TimeInterval = 0.03

    init(
        isDragSessionActive: @escaping @MainActor () -> Bool = DragMonitor.hasActiveDragWindow
    ) {
        self.isDragSessionActive = isDragSessionActive
    }

    deinit {
        MainActor.assumeIsolated {
            if let m = dragMonitor { NSEvent.removeMonitor(m) }
            if let m = upMonitor { NSEvent.removeMonitor(m) }
        }
    }

    func start() {
        guard dragMonitor == nil, upMonitor == nil else { return }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            self?.handleDrag(
                at: NSEvent.mouseLocation,
                now: ProcessInfo.processInfo.systemUptime
            )
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.handleMouseUp()
        }
    }

    func stop() {
        if let m = dragMonitor { NSEvent.removeMonitor(m) }
        if let m = upMonitor { NSEvent.removeMonitor(m) }
        dragMonitor = nil
        upMonitor = nil
        inDrag = false
        lastPoll = 0
    }

    func endOwnDrag() {
        let wasInDrag = inDrag
        inDrag = false
        lastPoll = 0
        if wasInDrag {
            dragEnded()
        }
    }

    func handleDrag(at point: NSPoint, now: TimeInterval) {
        if inDrag {
            dragMoved(point)
            return
        }

        guard now - lastPoll >= Self.pollInterval else { return }
        lastPoll = now
        guard isDragSessionActive() else { return }

        inDrag = true
        dragStarted()
        dragMoved(point)
    }

    func handleMouseUp() {
        lastPoll = 0
        guard inDrag else { return }
        inDrag = false
        dragEnded()
    }

    private static func hasActiveDragWindow() -> Bool {
        guard
            let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else { return false }

        return windows.contains {
            ($0[kCGWindowLayer as String] as? Int) == Int(kCGDraggingWindowLevel)
        }
    }
}
