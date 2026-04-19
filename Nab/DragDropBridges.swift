import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Window drag handle

/// Background view for the shelf header that lets the user drag the window by
/// clicking the chrome. Calls `onDragEnded` once when the user releases after
/// having actually moved the window, so the panel can persist its position.
struct WindowDragHandle: NSViewRepresentable {
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> DragHandleView {
        let view = DragHandleView()
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: DragHandleView, context: Context) {
        nsView.onDragEnded = onDragEnded
    }

    final class DragHandleView: NSView {
        var onDragEnded: () -> Void = {}
        private var startMouse: NSPoint?
        private var startOrigin: NSPoint?
        private var didDrag = false

        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            startMouse = NSEvent.mouseLocation
            startOrigin = window.frame.origin
            didDrag = false
            Log.shelf.debug("mouseDown origin=\(window.frame.origin.debugDescription, privacy: .public)")
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window, let sm = startMouse, let so = startOrigin else { return }
            let m = NSEvent.mouseLocation
            window.setFrameOrigin(NSPoint(x: so.x + m.x - sm.x, y: so.y + m.y - sm.y))
            didDrag = true
        }

        override func mouseUp(with event: NSEvent) {
            let origin = window?.frame.origin ?? .zero
            Log.shelf.debug(
                "mouseUp didDrag=\(self.didDrag) origin=\(origin.debugDescription, privacy: .public)"
            )
            if didDrag { onDragEnded() }
            startMouse = nil
            startOrigin = nil
            didDrag = false
        }
    }
}

// MARK: - File drag source

/// SwiftUI view that hosts arbitrary content but lets us drive an AppKit
/// `NSDraggingSession` directly, so we can: (1) drag multiple selected items as
/// one stack, (2) supply our thumbnail as the drag image, and (3) detect Finder
/// same-folder rejects so we can still treat them as moves.
struct FileDragSource<Content: View>: NSViewRepresentable {
    let itemID: ShelfItem.ID
    let model: ShelfModel
    let dragImage: NSImage?
    let onDragEnded: () -> Void
    let onQuickLook: () -> Void
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> FileDragSourceView {
        let host = NSHostingView(rootView: content())
        host.translatesAutoresizingMaskIntoConstraints = false
        let view = FileDragSourceView()
        view.itemID = itemID
        view.model = model
        view.dragImage = dragImage
        view.onDragEnded = onDragEnded
        view.onQuickLook = onQuickLook
        view.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: view.topAnchor),
            host.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        view.hostingView = host
        return view
    }

    func updateNSView(_ nsView: FileDragSourceView, context: Context) {
        nsView.itemID = itemID
        nsView.model = model
        nsView.dragImage = dragImage
        nsView.onDragEnded = onDragEnded
        nsView.onQuickLook = onQuickLook
        (nsView.hostingView as? NSHostingView<Content>)?.rootView = content()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FileDragSourceView, context: Context) -> CGSize? {
        let intrinsic = nsView.hostingView?.intrinsicContentSize ?? .zero
        return CGSize(
            width: proposal.width ?? intrinsic.width,
            height: proposal.height ?? intrinsic.height
        )
    }
}

final class FileDragSourceView: NSView, NSDraggingSource {
    var itemID: ShelfItem.ID?
    weak var model: ShelfModel?
    var dragImage: NSImage?
    var onDragEnded: () -> Void = {}
    var onQuickLook: () -> Void = {}
    weak var hostingView: NSView?

    private var mouseDownLocation: NSPoint?
    private var pendingClickAction: (() -> Void)?
    private var cursorInsideShelf = true
    private var didForceClick = false
    private var draggedIDs: [ShelfItem.ID] = []
    private static let dragThreshold: CGFloat = 3

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        pressureConfiguration = NSPressureConfiguration(pressureBehavior: .primaryDeepClick)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        Log.shelf.debug("FileDragSource mouseDown clickCount=\(event.clickCount)")
        didForceClick = false
        guard let itemID, let model else { return }

        if event.clickCount == 2 {
            mouseDownLocation = nil
            pendingClickAction = nil
            guard let url = model.resolveURL(for: itemID) else {
                model.remove(itemID)
                return
            }
            Log.shelf.debug("FileDragSource opening \(url.path, privacy: .public)")
            NSWorkspace.shared.open(url)
            return
        }

        mouseDownLocation = event.locationInWindow
        pendingClickAction = nil

        let modifiers = event.modifierFlags
        if modifiers.contains(.shift) {
            model.extendSelection(to: itemID)
        } else if modifiers.contains(.command) {
            if model.isSelected(itemID) {
                // Defer removal — a drag should carry the clicked item along
                // with the rest of the selection rather than dropping it.
                pendingClickAction = { [weak model] in
                    model?.toggleSelection(itemID)
                }
            } else {
                model.toggleSelection(itemID)
            }
        } else if model.isSelected(itemID) {
            // Defer so a drag uses the whole selection; only apply on release.
            pendingClickAction = { [weak model] in
                model?.plainClick(itemID)
            }
        } else {
            model.plainClick(itemID)
        }
    }

    override func pressureChange(with event: NSEvent) {
        guard !didForceClick, event.stage >= 2 else { return }
        didForceClick = true
        mouseDownLocation = nil
        pendingClickAction = nil
        Log.shelf.debug("FileDragSource force click")
        onQuickLook()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let dx = event.locationInWindow.x - start.x
        let dy = event.locationInWindow.y - start.y
        guard hypot(dx, dy) > Self.dragThreshold else { return }
        mouseDownLocation = nil
        pendingClickAction = nil
        startDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        Log.shelf.debug("FileDragSource mouseUp clickCount=\(event.clickCount)")
        mouseDownLocation = nil
        pendingClickAction?()
        pendingClickAction = nil
    }

    private func startDrag(with event: NSEvent) {
        guard let itemID, let model else { return }
        model.ensureSelectedForDrag(itemID)
        let selected = model.selectedItemsInOrder()

        var dragItems: [NSDraggingItem] = []
        var successfulIDs: [ShelfItem.ID] = []
        var missingIDs: [ShelfItem.ID] = []
        let dragSize: CGFloat = 48
        let clickLocation = convert(event.locationInWindow, from: nil)

        for (index, shelfItem) in selected.enumerated() {
            guard let url = model.resolveURL(for: shelfItem.id) else {
                missingIDs.append(shelfItem.id)
                continue
            }
            let image: NSImage = {
                if shelfItem.id == itemID, let dragImage, let copy = dragImage.copy() as? NSImage {
                    copy.size = NSSize(width: dragSize, height: dragSize)
                    return copy
                }
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: dragSize, height: dragSize)
                return icon
            }()
            let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
            // Offset secondary items to suggest a stack behind the primary.
            let offset: CGFloat = shelfItem.id == itemID ? 0 : CGFloat(index) * 4
            draggingItem.setDraggingFrame(
                NSRect(
                    x: clickLocation.x - dragSize / 2 + offset,
                    y: clickLocation.y - dragSize / 2 - offset,
                    width: dragSize,
                    height: dragSize
                ),
                contents: image
            )
            dragItems.append(draggingItem)
            successfulIDs.append(shelfItem.id)
        }

        if !missingIDs.isEmpty {
            model.remove(ids: missingIDs)
        }

        guard !dragItems.isEmpty else {
            NSAnimationEffect.poof.show(
                centeredAt: NSEvent.mouseLocation,
                size: NSSize(width: 32, height: 32)
            )
            onDragEnded()
            return
        }

        draggedIDs = successfulIDs
        cursorInsideShelf = true
        beginDraggingSession(with: dragItems, event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        [.move, .copy]
    }

    func draggingSession(
        _ session: NSDraggingSession,
        movedTo screenPoint: NSPoint
    ) {
        guard let shelfFrame = window?.frame else { return }
        let inside = shelfFrame.contains(screenPoint)
        guard inside != cursorInsideShelf else { return }
        cursorInsideShelf = inside
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        if operation == .move || droppedOnFinderWindow(at: screenPoint) {
            model?.remove(ids: draggedIDs)
        }
        draggedIDs = []
        onDragEnded()
    }

    /// Finder rejects same-folder drops with `.none`, so a `.none` result over a
    /// Finder window implies the user dragged the file back where it came from;
    /// treat that as a logical move and clear the shelf entry.
    private func droppedOnFinderWindow(at screenPoint: NSPoint) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]],
            let primary = NSScreen.screens.first
        else { return false }
        let cgY = primary.frame.maxY - screenPoint.y
        for info in infos {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                let bounds = info[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }
            let x = bounds["X"] ?? 0
            let y = bounds["Y"] ?? 0
            let w = bounds["Width"] ?? 0
            let h = bounds["Height"] ?? 0
            guard screenPoint.x >= x, screenPoint.x <= x + w, cgY >= y, cgY <= y + h else { continue }
            return (info[kCGWindowOwnerName as String] as? String) == "Finder"
        }
        return false
    }
}

// MARK: - Shelf drop target

/// NSView-based drop target. Reads the raw drag pasteboard so we can see
/// `public.file-url` even when a dragged item also exposes image data — SwiftUI's
/// `.onDrop(of:)` filters the NSItemProvider to the most specific accepted type
/// and strips the file URL for items like PNG files from Finder.
struct ShelfDropTarget: NSViewRepresentable {
    let onDrop: ([URL]) -> Void

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.onDrop = onDrop
        return view
    }

    func updateNSView(_ nsView: DropView, context: Context) {
        nsView.onDrop = onDrop
    }

    final class DropView: NSView {
        var onDrop: ([URL]) -> Void = { _ in }

        private static let imageTypes: [(NSPasteboard.PasteboardType, String)] = [
            (NSPasteboard.PasteboardType(UTType.png.identifier), "png"),
            (NSPasteboard.PasteboardType(UTType.jpeg.identifier), "jpg"),
            (NSPasteboard.PasteboardType(UTType.heic.identifier), "heic"),
            (NSPasteboard.PasteboardType(UTType.tiff.identifier), "tiff"),
            (NSPasteboard.PasteboardType(UTType.gif.identifier), "gif"),
        ]

        private static let screenshotFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            return formatter
        }()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            var types: [NSPasteboard.PasteboardType] = [.fileURL]
            types.append(contentsOf: Self.imageTypes.map(\.0))
            registerForDraggedTypes(types)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let pasteboard = sender.draggingPasteboard
            var urls: [URL] = []

            // Prefer file URLs when present — covers Finder drags of any file type.
            let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            if let fileURLs = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: fileOptions
            ) as? [URL] {
                urls.append(contentsOf: fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) })
            }

            // Fall back to image data — covers ad hoc screenshots (Cmd+Shift+4 thumbnail)
            // and dragged images that expose no file URL on the pasteboard.
            if urls.isEmpty {
                for item in pasteboard.pasteboardItems ?? [] {
                    for (type, ext) in Self.imageTypes where item.types.contains(type) {
                        guard let data = item.data(forType: type),
                            let url = Self.saveScreenshot(data: data, ext: ext)
                        else { continue }
                        urls.append(url)
                        break
                    }
                }
            }

            guard !urls.isEmpty else { return false }
            onDrop(urls)
            return true
        }

        private static func saveScreenshot(data: Data, ext: String) -> URL? {
            let filename = "Screenshot \(screenshotFormatter.string(from: Date())).\(ext)"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            do {
                try data.write(to: url, options: .atomic)
                return url
            } catch {
                return nil
            }
        }
    }
}
