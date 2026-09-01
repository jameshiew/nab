import AppKit

/// Watches for system-wide left-button drag sessions.
/// Posts `dragStarted` once per drag, then `dragEnded` on mouse up.
final class DragMonitor {
    var dragStarted: () -> Void = {}
    var dragEnded: () -> Void = {}
    var dragMoved: (NSPoint) -> Void = { _ in }

    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var inDrag = false

    deinit {
        MainActor.assumeIsolated {
            if let m = dragMonitor { NSEvent.removeMonitor(m) }
            if let m = upMonitor { NSEvent.removeMonitor(m) }
        }
    }

    func start() {
        guard dragMonitor == nil, upMonitor == nil else { return }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            self?.handleDrag()
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.handleUp()
        }
    }

    func stop() {
        if let m = dragMonitor { NSEvent.removeMonitor(m) }
        if let m = upMonitor { NSEvent.removeMonitor(m) }
        dragMonitor = nil
        upMonitor = nil
        inDrag = false
    }

    func endOwnDrag() {
        let wasInDrag = inDrag
        inDrag = false
        if wasInDrag {
            dragEnded()
        }
    }

    private func handleDrag() {
        if inDrag {
            dragMoved(NSEvent.mouseLocation)
            return
        }

        inDrag = true
        dragStarted()
        dragMoved(NSEvent.mouseLocation)
    }

    private func handleUp() {
        guard inDrag else { return }
        inDrag = false
        dragEnded()
    }
}
