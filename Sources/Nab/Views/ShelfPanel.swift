import AppKit
import SwiftUI

final class ShelfPanel: NSPanel {
    struct Display {
        let id: CGDirectDisplayID
        let frame: CGRect
        let visibleFrame: CGRect
    }

    static let width: CGFloat = 220
    static let baseHeight = PanelGeometry.baseHeight
    static let edgeInset: CGFloat = 12

    private let displays: @MainActor () -> [Display]
    private var presentationDisplayID: CGDirectDisplayID?
    private var itemCount = 0
    private var isShown = false
    private var customTopLeft: CGPoint?
    private var moveObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?

    var currentHeight: CGFloat { visibleFrame.height }
    var size: CGSize { visibleFrame.size }

    init(
        rootView: some View,
        displays: @escaping @MainActor () -> [Display] = ShelfPanel.availableDisplays,
        customTopLeft: CGPoint? = ShelfPreferences.topLeft
    ) {
        self.displays = displays
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        self.customTopLeft = customTopLeft
        presentationDisplayID = display(at: NSEvent.mouseLocation)?.id

        let host = NSHostingView(rootView: rootView)
        host.translatesAutoresizingMaskIntoConstraints = false
        contentView = NSView()
        contentView?.addSubview(host)
        if let cv = contentView {
            NSLayoutConstraint.activate([
                host.topAnchor.constraint(equalTo: cv.topAnchor),
                host.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
                host.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            ])
        }

        setFrame(edgeFrame, display: false)

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                Log.shelf.debug("windowDidMove frame=\(self.frame.debugDescription, privacy: .public)")
            }
        }

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isShown else { return }
                Log.shelf.debug(
                    "activeSpaceDidChange isVisible=\(self.isVisible) isOnActiveSpace=\(self.isOnActiveSpace)"
                )
                self.orderFrontRegardless()
            }
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restoreAfterDisplayChange()
            }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let moveObserver {
                NotificationCenter.default.removeObserver(moveObserver)
            }
            if let spaceObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
            }
            if let screenObserver {
                NotificationCenter.default.removeObserver(screenObserver)
            }
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var visibleFrame: NSRect {
        let screen =
            presentationDisplay?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: Self.width, height: Self.baseHeight)
        return PanelGeometry.visibleFrame(
            width: Self.width,
            itemCount: itemCount,
            customTopLeft: customTopLeft,
            edgeInset: Self.edgeInset,
            in: screen
        )
    }

    var edgeFrame: NSRect {
        PanelGeometry.frameAtNearestHorizontalEdge(
            for: visibleFrame,
            in: displays().map(\.frame)
        )
    }

    func userDidFinishDragging() {
        let matchingDisplay = displayBestMatching(frame)
        let isOnScreen =
            matchingDisplay.map {
                ScreenGeometry.intersectionArea(frame, $0.visibleFrame) > 0
            } ?? false
        let proposed = isOnScreen ? frame : visibleFrame
        let targetDisplay = isOnScreen ? matchingDisplay : presentationDisplay
        presentationDisplayID = targetDisplay?.id
        let screen = targetDisplay?.visibleFrame ?? proposed
        let savedFrame = PanelGeometry.resizedVisibleFrame(
            for: proposed,
            itemCount: itemCount,
            in: screen
        )
        if savedFrame != frame {
            setFrame(savedFrame, display: true)
        }

        let topLeft = CGPoint(x: savedFrame.minX, y: savedFrame.maxY)
        Log.shelf.debug(
            "userDidFinishDragging saving top=\(topLeft.debugDescription, privacy: .public) frame=\(savedFrame.debugDescription, privacy: .public)"
        )
        customTopLeft = topLeft
        ShelfPreferences.topLeft = topLeft
    }

    func slideIn(at point: NSPoint = NSEvent.mouseLocation) {
        let previousDisplayID = presentationDisplayID
        presentationDisplayID = display(at: point)?.id
        let target = visibleFrame
        if !isShown || previousDisplayID != presentationDisplayID {
            setFrame(edgeFrame, display: false)
        }
        Log.shelf.debug("slideIn target=\(target.debugDescription, privacy: .public)")
        isShown = true
        orderFrontRegardless()
        animate(to: target)
        recordPresentationEvent("shelf_presented")
    }

    func slideOut() {
        let target = edgeFrame
        Log.shelf.debug("slideOut target=\(target.debugDescription, privacy: .public)")
        isShown = false
        animate(to: target) { [weak self] in
            guard let self, !self.isShown else { return }
            self.orderOut(nil)
        }
    }

    func updateHeight(forItemCount count: Int) {
        itemCount = count
        guard abs(visibleFrame.height - frame.height) > 0.5 else { return }
        if isShown {
            animate(to: visibleFrame)
        } else {
            setFrame(edgeFrame, display: false)
        }
    }

    private func animate(
        to frame: NSRect,
        completionHandler: (@MainActor @Sendable () -> Void)? = nil
    ) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            self.animator().setFrame(frame, display: true)
        } completionHandler: {
            Task { @MainActor in
                completionHandler?()
            }
        }
    }

    private var presentationDisplay: Display? {
        let available = displays()
        return available.first { $0.id == presentationDisplayID } ?? available.first
    }

    private func display(at point: NSPoint) -> Display? {
        let available = displays()
        return available.first { $0.frame.contains(point) } ?? presentationDisplay
    }

    private func displayBestMatching(_ rect: NSRect) -> Display? {
        let screens = displays()
        let frames = screens.map(\.visibleFrame)
        guard let index = ScreenGeometry.bestMatchingIndex(for: rect, in: frames) else { return nil }
        return screens[index]
    }

    private func restoreAfterDisplayChange() {
        if !displays().contains(where: { $0.id == presentationDisplayID }) {
            presentationDisplayID = display(at: NSEvent.mouseLocation)?.id
        }
        let target = isShown ? visibleFrame : edgeFrame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            self.animator().setFrame(target, display: self.isShown)
        }
        if isShown {
            orderFrontRegardless()
        } else {
            orderOut(nil)
        }
        recordPresentationEvent("display_configuration_changed")
    }

    private func recordPresentationEvent(_ name: String) {
        DiagnosticsRecorder.shared.record(
            name,
            details: [
                "display_id": presentationDisplayID.map(String.init) ?? "none",
                "frame": NSStringFromRect(frame),
                "is_on_active_space": String(isOnActiveSpace),
                "is_shown": String(isShown),
                "is_visible": String(isVisible),
            ]
        )
    }

    private static func availableDisplays() -> [Display] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.cgDirectDisplayID else { return nil }
            return Display(id: id, frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
    }
}
