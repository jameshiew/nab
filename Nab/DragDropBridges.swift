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
/// one stack and (2) supply our thumbnail as the drag image.
struct FileDragSource<Content: View>: NSViewRepresentable {
    let itemID: ShelfItem.ID
    let model: ShelfModel
    let dragImage: NSImage?
    let onDragEnded: () -> Void
    let onForceClick: () -> Void
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> FileDragSourceView {
        let host = NSHostingView(rootView: content())
        host.translatesAutoresizingMaskIntoConstraints = false
        let view = FileDragSourceView()
        view.itemID = itemID
        view.model = model
        view.dragImage = dragImage
        view.onDragEnded = onDragEnded
        view.onForceClick = onForceClick
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
        nsView.onForceClick = onForceClick
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
    var onForceClick: () -> Void = {}
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
            let urls = model.resolveURLs(for: itemID)
            for url in urls {
                Log.shelf.debug("FileDragSource opening \(url.path, privacy: .public)")
                NSWorkspace.shared.open(url)
            }
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
        onForceClick()
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

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let itemID, let model else { return nil }
        let urls = model.resolveURLs(for: itemID)
        guard !urls.isEmpty else { return nil }

        let menu = NSMenu()
        if urls.count == 1 {
            menu.addItem(showInFinderMenuItem(for: urls[0]))
        } else {
            let item = NSMenuItem(title: "Show in Finder", action: nil, keyEquivalent: "")
            item.image = Self.finderMenuIcon()

            let submenu = NSMenu(title: "Show in Finder")
            for url in urls {
                let title = Self.menuTitle(for: url)
                let image = Self.fileMenuIcon(for: url)
                submenu.addItem(showInFinderMenuItem(for: url, title: title, image: image))
            }
            item.submenu = submenu
            menu.addItem(item)
        }
        return menu
    }

    @objc private func showInFinder(_ sender: NSMenuItem) {
        let url =
            (sender.representedObject as? URL)
            ?? (sender.representedObject as? NSURL).map { $0 as URL }
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func startDrag(with event: NSEvent) {
        guard let itemID, let model else { return }
        model.ensureSelectedForDrag(itemID)
        let selected = model.selectedItemsInOrder()

        var dragItems: [NSDraggingItem] = []
        var successfulIDs: [ShelfItem.ID] = []
        let dragSize: CGFloat = 48
        let clickLocation = convert(event.locationInWindow, from: nil)
        // Stack offset is global across all dragged files so a multi-item
        // selection that includes stacks still fans out nicely.
        var stackIndex = 0

        for shelfItem in selected {
            let urls = model.resolveURLs(for: shelfItem.id)
            // resolveURLs auto-removes an item whose files have all gone missing.
            if urls.isEmpty { continue }
            let isClickedItem = shelfItem.id == itemID
            for (entryIdx, url) in urls.enumerated() {
                let isPrimary = isClickedItem && entryIdx == 0
                let image: NSImage = {
                    if isPrimary, let dragImage, let copy = dragImage.copy() as? NSImage {
                        copy.size = NSSize(width: dragSize, height: dragSize)
                        return copy
                    }
                    let icon = NSWorkspace.shared.icon(forFile: url.path)
                    icon.size = NSSize(width: dragSize, height: dragSize)
                    return icon
                }()
                let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
                let offset: CGFloat = isPrimary ? 0 : CGFloat(stackIndex) * 4
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
                stackIndex += 1
            }
            successfulIDs.append(shelfItem.id)
        }

        guard !dragItems.isEmpty else {
            ShelfFeedback.rejectedDrop()
            onDragEnded()
            return
        }

        draggedIDs = successfulIDs
        cursorInsideShelf = true
        beginDraggingSession(with: dragItems, event: event, source: self)
    }

    private func showInFinderMenuItem(for url: URL, title: String = "Show in Finder") -> NSMenuItem {
        showInFinderMenuItem(for: url, title: title, image: Self.finderMenuIcon())
    }

    private func showInFinderMenuItem(for url: URL, title: String, image: NSImage?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(showInFinder(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = url as NSURL
        item.image = image
        return item
    }

    private static func menuTitle(for url: URL) -> String {
        url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    private static func finderMenuIcon() -> NSImage? {
        NSImage(systemSymbolName: "finder", accessibilityDescription: "Finder")
    }

    private static func fileMenuIcon(for url: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
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
        if DragOperationPolicy.shouldRemoveItems(after: operation) {
            model?.remove(ids: draggedIDs)
        }
        draggedIDs = []
        onDragEnded()
    }
}

// MARK: - Shelf drop target

/// NSView-based drop target. Reads the raw drag pasteboard so we can see
/// `public.file-url` even when a dragged item also exposes image data — SwiftUI's
/// `.onDrop(of:)` filters the NSItemProvider to the most specific accepted type
/// and strips the file URL for items like PNG files from Finder.
struct ShelfDropTarget: NSViewRepresentable {
    let onDrop: ([FileEntry]) -> Void

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.onDrop = onDrop
        return view
    }

    func updateNSView(_ nsView: DropView, context: Context) {
        nsView.onDrop = onDrop
    }

    final class DropView: NSView {
        var onDrop: ([FileEntry]) -> Void = { _ in }

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
            var entries: [FileEntry] = []

            // Prefer file URLs when present — covers Finder drags of any file type.
            entries.append(contentsOf: Self.fileURLs(from: pasteboard).map { FileEntry(url: $0) })

            // Fall back to image data — covers ad hoc screenshots (Cmd+Shift+4 thumbnail)
            // and dragged images that expose no file URL on the pasteboard.
            if entries.isEmpty {
                for item in pasteboard.pasteboardItems ?? [] {
                    for (type, ext) in Self.imageTypes where item.types.contains(type) {
                        guard let data = item.data(forType: type),
                            let url = Self.saveScreenshot(data: data, ext: ext)
                        else { continue }
                        entries.append(FileEntry(url: url, isMaterializedByNab: true))
                        break
                    }
                }
            }

            guard !entries.isEmpty else { return false }
            onDrop(entries)
            return true
        }

        private static func saveScreenshot(data: Data, ext: String) -> URL? {
            let filename = "Screenshot \(screenshotFormatter.string(from: Date()))-\(UUID().uuidString).\(ext)"
            do {
                let directory = try materializedImageDirectory()
                let url = directory.appendingPathComponent(filename)
                try data.write(to: url, options: .atomic)
                return url
            } catch {
                Log.shelf.error("Failed to materialize dropped image: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }

        private static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
            let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) ?? []
            return objects.compactMap { object in
                if let url = object as? URL {
                    return url
                }
                if let url = object as? NSURL {
                    return url as URL
                }
                return nil
            }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        }

        private static func materializedImageDirectory() throws -> URL {
            let manager = FileManager.default
            let baseURL =
                manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? manager.temporaryDirectory
            let directory =
                baseURL
                .appendingPathComponent("Nab", isDirectory: true)
                .appendingPathComponent("Dropped Images", isDirectory: true)
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }
}
