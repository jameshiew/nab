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
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var visibleFrame: NSRect {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let x = screen.maxX - size.width - Self.edgeInset
        let y = screen.midY - size.height / 2
        return NSRect(origin: CGPoint(x: x, y: y), size: size)
    }

    var hiddenFrame: NSRect {
        let screen = NSScreen.main?.frame ?? .zero
        let visible = visibleFrame
        return NSRect(
            x: screen.maxX + Self.edgeInset,
            y: visible.origin.y,
            width: size.width,
            height: size.height
        )
    }

    func slideIn() {
        isShown = true
        animate(to: visibleFrame)
    }

    func slideOut() {
        isShown = false
        animate(to: hiddenFrame)
    }

    func updateHeight(forItemCount count: Int) {
        let needed: CGFloat = {
            guard count > 0 else { return Self.baseHeight }
            let rows = CGFloat(count) * Self.rowHeight + CGFloat(count - 1) * Self.rowSpacing
            return Self.chromeHeight + Self.contentVerticalPadding + rows
        }()
        let screenHeight = NSScreen.main?.visibleFrame.height ?? Self.baseHeight
        let maxAllowed = max(Self.baseHeight, screenHeight - Self.screenMargin)
        let newHeight = min(max(Self.baseHeight, needed), maxAllowed)
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
}
