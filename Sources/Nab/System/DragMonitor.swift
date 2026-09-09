import AppKit
import CoreGraphics

final class DragMonitor {
    var dragStarted: () -> Void = {}
    var dragEnded: () -> Void = {}
    var dragMoved: (NSPoint) -> Void = { _ in }

    private let isDragSessionActive: @MainActor () -> Bool
    private var pollTimer: Timer?
    private var inDrag = false

    private static let pollInterval: TimeInterval = 0.05

    init(
        isDragSessionActive: @escaping @MainActor () -> Bool = DragMonitor.hasActiveDragWindow
    ) {
        self.isDragSessionActive = isDragSessionActive
    }

    deinit {
        MainActor.assumeIsolated {
            pollTimer?.invalidate()
        }
    }

    func start() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll(at: NSEvent.mouseLocation)
            }
        }
        timer.tolerance = 0.01
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        inDrag = false
    }

    func endDrag() {
        let wasInDrag = inDrag
        inDrag = false
        if wasInDrag {
            dragEnded()
        }
    }

    func poll(at point: NSPoint) {
        guard isDragSessionActive() else {
            endDrag()
            return
        }

        if !inDrag {
            inDrag = true
            dragStarted()
        }
        dragMoved(point)
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
