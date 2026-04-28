import AppKit
import SwiftUI

final class ShelfPanel: NSPanel {
    static let width: CGFloat = 220
    static let baseHeight: CGFloat = 360
    static let edgeInset: CGFloat = 12

    /// Per-icon row height: 96 thumbnail + 6 spacing + ~16 caption + 8 ShelfIcon padding.
    private static let rowHeight: CGFloat = 126
    private static let rowSpacing: CGFloat = 12
    /// Header (~26) + Divider (1).
    private static let chromeHeight: CGFloat = 27
    /// Top + bottom padding inside the LazyVStack.
    private static let contentVerticalPadding: CGFloat = 24
    private static let screenMargin: CGFloat = 80

    private(set) var currentHeight: CGFloat = baseHeight
    private var isShown = false
    private var customTopLeft: CGPoint?
    private var moveObserver: NSObjectProtocol?

    var size: CGSize { CGSize(width: Self.width, height: currentHeight) }

    init(rootView: some View) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        customTopLeft = ShelfPreferences.topLeft

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

        setFrame(hiddenFrame, display: false)
        orderFrontRegardless()

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
    }

    deinit {
        MainActor.assumeIsolated {
            if let moveObserver {
                NotificationCenter.default.removeObserver(moveObserver)
            }
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var visibleFrame: NSRect {
        if let top = customTopLeft {
            let proposed = NSRect(
                x: top.x,
                y: top.y - size.height,
                width: size.width,
                height: size.height
            )
            if let frame = Self.clampedVisibleFrame(for: proposed) {
                return frame
            }
            Log.shelf.debug(
                "visibleFrame custom OFF-SCREEN top=\(top.debugDescription, privacy: .public) proposed=\(proposed.debugDescription, privacy: .public)"
            )
        }
        return Self.defaultVisibleFrame(for: size)
    }

    var hiddenFrame: NSRect {
        let visible = visibleFrame
        let screenFrame = Self.screenBestMatching(visible)?.frame ?? (NSScreen.main?.frame ?? .zero)
        return NSRect(
            x: screenFrame.maxX + Self.edgeInset,
            y: visible.origin.y,
            width: size.width,
            height: size.height
        )
    }

    func userDidFinishDragging() {
        let savedFrame = Self.clampedVisibleFrame(for: frame) ?? Self.defaultVisibleFrame(for: size)
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

    func slideIn() {
        let target = visibleFrame
        Log.shelf.debug("slideIn target=\(target.debugDescription, privacy: .public)")
        isShown = true
        animate(to: target)
    }

    func slideOut() {
        let target = hiddenFrame
        Log.shelf.debug("slideOut target=\(target.debugDescription, privacy: .public)")
        isShown = false
        animate(to: target)
    }

    func updateHeight(forItemCount count: Int) {
        let needed: CGFloat = {
            guard count > 0 else { return Self.baseHeight }
            let rows = CGFloat(count) * Self.rowHeight + CGFloat(count - 1) * Self.rowSpacing
            return Self.chromeHeight + Self.contentVerticalPadding + rows
        }()
        let screenHeight =
            Self.screenBestMatching(visibleFrame)?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? Self.baseHeight
        let minimumHeight = min(Self.baseHeight, screenHeight)
        let maxAllowed = max(minimumHeight, screenHeight - Self.screenMargin)
        let newHeight = min(max(minimumHeight, needed), maxAllowed)
        guard abs(newHeight - currentHeight) > 0.5 else { return }
        currentHeight = newHeight
        if isShown {
            animate(to: visibleFrame)
        } else {
            setFrame(hiddenFrame, display: false)
        }
    }

    private func animate(to frame: NSRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            self.animator().setFrame(frame, display: true)
        }
    }

    private static func defaultVisibleFrame(for size: CGSize) -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(origin: .zero, size: size)
        let proposed = NSRect(
            x: screen.maxX - size.width - edgeInset,
            y: screen.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        return clampedFrame(proposed, to: screen)
    }

    private static func clampedVisibleFrame(for proposed: NSRect) -> NSRect? {
        guard let screen = screenBestMatching(proposed),
            intersectionArea(proposed, screen.visibleFrame) > 0
        else {
            return nil
        }
        return clampedFrame(proposed, to: screen.visibleFrame)
    }

    private static func screenBestMatching(_ rect: NSRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            intersectionArea(rect, lhs.visibleFrame) < intersectionArea(rect, rhs.visibleFrame)
        }
    }

    private static func clampedFrame(_ frame: NSRect, to bounds: NSRect) -> NSRect {
        let maxX = max(bounds.minX, bounds.maxX - frame.width)
        let maxY = max(bounds.minY, bounds.maxY - frame.height)
        let x = min(max(frame.minX, bounds.minX), maxX)
        let y = min(max(frame.minY, bounds.minY), maxY)
        return NSRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    private static func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return max(0, intersection.width) * max(0, intersection.height)
    }
}
