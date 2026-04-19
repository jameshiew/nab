import AppKit
import SwiftUI

final class ShelfPanel: NSPanel {
    static let size = CGSize(width: 220, height: 360)
    static let edgeInset: CGFloat = 12

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
        let x = screen.maxX - Self.size.width - Self.edgeInset
        let y = screen.midY - Self.size.height / 2
        return NSRect(origin: CGPoint(x: x, y: y), size: Self.size)
    }

    var hiddenFrame: NSRect {
        let screen = NSScreen.main?.frame ?? .zero
        let visible = visibleFrame
        return NSRect(
            x: screen.maxX + Self.edgeInset,
            y: visible.origin.y,
            width: Self.size.width,
            height: Self.size.height
        )
    }

    func slideIn() { animate(to: visibleFrame) }
    func slideOut() { animate(to: hiddenFrame) }

    private func animate(to frame: NSRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            self.animator().setFrame(frame, display: true)
        }
    }
}
