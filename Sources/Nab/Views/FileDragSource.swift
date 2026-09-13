import AppKit
import SwiftUI

/// SwiftUI view that hosts arbitrary content but lets us drive an AppKit
/// `NSDraggingSession` directly, so we can: (1) drag multiple selected items as
/// one stack and (2) supply our thumbnail as the drag image.
struct FileDragSource<Content: View>: NSViewRepresentable {
    let itemID: ShelfItem.ID
    let model: ShelfModel
    let exportCoordinator: FileExportCoordinator
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
        view.exportCoordinator = exportCoordinator
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
        nsView.exportCoordinator = exportCoordinator
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
    var exportCoordinator: FileExportCoordinator?
    var dragImage: NSImage?
    var onDragEnded: () -> Void = {}
    var onForceClick: () -> Void = {}
    weak var hostingView: NSView?

    private var mouseDownLocation: NSPoint?
    private var pendingClickAction: (() -> Void)?
    private var cursorInsideShelf = true
    private var didForceClick = false
    private var activeExportID: FileExportCoordinator.ExportID?
    private var dragContainsMaterializedFiles = false
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
                Log.shelf.debug(
                    "FileDragSource opening \(url.path, privacy: .private(mask: .hash))"
                )
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
        guard let exportCoordinator else { return }
        let exportID = exportCoordinator.beginExport()
        dragContainsMaterializedFiles = false
        let dragSize: CGFloat = 48
        let clickLocation = convert(event.locationInWindow, from: nil)
        // Stack offset is global across all dragged files so a multi-item
        // selection that includes stacks still fans out nicely.
        var stackIndex = 0

        for shelfItem in selected {
            let urls = model.resolveURLs(for: shelfItem.id)
            // resolveURLs auto-removes an item whose files have all gone missing.
            if urls.isEmpty { continue }
            guard let resolvedItem = model.items.first(where: { $0.id == shelfItem.id }) else {
                continue
            }
            exportCoordinator.registerItem(shelfItem.id, in: exportID)
            let isClickedItem = shelfItem.id == itemID
            for (entryIdx, entry) in resolvedItem.entries.enumerated() {
                let url = entry.url
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
                if entry.isMaterializedByNab {
                    exportCoordinator.retainMaterializedFile(url, in: exportID)
                    dragContainsMaterializedFiles = true
                }
                let pasteboardWriter = Self.pasteboardWriter(for: entry)
                let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardWriter)
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
        }

        guard !dragItems.isEmpty else {
            exportCoordinator.cancelExport(exportID)
            ShelfFeedback.rejectedDrop()
            onDragEnded()
            return
        }

        activeExportID = exportID
        cursorInsideShelf = true
        beginDraggingSession(with: dragItems, event: event, source: self)
    }

    static func pasteboardWriter(for entry: FileEntry) -> NSPasteboardWriting {
        entry.url as NSURL
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
        DragOperationPolicy.sourceMask(
            for: context,
            containsMaterializedFiles: dragContainsMaterializedFiles
        )
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
        if let activeExportID {
            exportCoordinator?.finishExport(activeExportID, operation: operation)
        }
        activeExportID = nil
        dragContainsMaterializedFiles = false
        onDragEnded()
    }
}
