import AppKit

/// Watches for system-wide drag sessions that carry file URLs.
/// Posts `dragStarted` once per drag, then `dragEnded` on mouse up.
final class DragMonitor {
    var dragStarted: () -> Void = {}
    var dragEnded: () -> Void = {}

    private let pasteboard = NSPasteboard(name: .drag)
    private var baselineChangeCount: Int
    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var inDrag = false
    private var lastPoll: TimeInterval = 0
    private static let pollInterval: TimeInterval = 0.03

    init() {
        baselineChangeCount = pasteboard.changeCount
    }

    func start() {
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
    }

    private func handleDrag() {
        if inDrag { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastPoll < Self.pollInterval { return }
        lastPoll = now

        let current = pasteboard.changeCount
        guard current != baselineChangeCount else { return }
        baselineChangeCount = current

        guard pasteboardHoldsFiles() else { return }

        inDrag = true
        dragStarted()
    }

    private func handleUp() {
        guard inDrag else { return }
        inDrag = false
        baselineChangeCount = pasteboard.changeCount
        dragEnded()
    }

    private func pasteboardHoldsFiles() -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return pasteboard.canReadObject(forClasses: [NSURL.self], options: options)
    }
}
