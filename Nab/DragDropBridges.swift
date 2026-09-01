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

// MARK: - Shelf drop target

/// NSView-based drop target. Reads the raw drag pasteboard so we can see
/// `public.file-url` even when a dragged item also exposes image data — SwiftUI's
/// `.onDrop(of:)` filters the NSItemProvider to the most specific accepted type
/// and strips the file URL for items like PNG files from Finder.
struct ShelfDropTarget: NSViewRepresentable {
    let materializedFileStore: MaterializedFileStore
    let onDrop: ([FileEntry]) -> Void
    let onPromiseDropStarted: () -> Void
    let onPromiseDropFinished: () -> Void

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.materializedFileStore = materializedFileStore
        view.onDrop = onDrop
        view.onPromiseDropStarted = onPromiseDropStarted
        view.onPromiseDropFinished = onPromiseDropFinished
        return view
    }

    func updateNSView(_ nsView: DropView, context: Context) {
        nsView.materializedFileStore = materializedFileStore
        nsView.onDrop = onDrop
        nsView.onPromiseDropStarted = onPromiseDropStarted
        nsView.onPromiseDropFinished = onPromiseDropFinished
    }

    final class DropView: NSView {
        var materializedFileStore: MaterializedFileStore = .shared
        var onDrop: ([FileEntry]) -> Void = { _ in }
        var onPromiseDropStarted: () -> Void = {}
        var onPromiseDropFinished: () -> Void = {}

        private struct PromiseDrop {
            let receivers: [NSFilePromiseReceiver]
            let destinationURL: URL
            var pendingReceiverIDs: Set<UUID>
            var entries: [FileEntry] = []
        }

        struct PendingImage: Sendable {
            let data: Data
            let destinationURL: URL
        }

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
        private let filePromiseQueue: OperationQueue = {
            let queue = OperationQueue()
            queue.qualityOfService = .userInitiated
            return queue
        }()
        private let imageWriteQueue: OperationQueue = {
            let queue = OperationQueue()
            queue.name = "dev.nab.dropped-image-write"
            queue.qualityOfService = .userInitiated
            queue.maxConcurrentOperationCount = 1
            return queue
        }()
        private var promiseDrops: [UUID: PromiseDrop] = [:]

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            var types = NSFilePromiseReceiver.readableDraggedTypes.map {
                NSPasteboard.PasteboardType($0)
            }
            types.append(.fileURL)
            types.append(contentsOf: Self.imageTypes.map(\.0))
            registerForDraggedTypes(types)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let pasteboard = sender.draggingPasteboard

            if receiveFilePromises(from: pasteboard) {
                return true
            }

            var entries: [FileEntry] = []

            entries.append(contentsOf: Self.fileURLs(from: pasteboard).map { FileEntry(url: $0) })

            if !entries.isEmpty {
                onDrop(entries)
                return true
            }

            return receiveImages(from: pasteboard)
        }

        private func receiveImages(from pasteboard: NSPasteboard) -> Bool {
            var images: [PendingImage] = []
            for item in pasteboard.pasteboardItems ?? [] {
                for (type, ext) in Self.imageTypes where item.types.contains(type) {
                    guard let data = item.data(forType: type) else { continue }
                    images.append(
                        PendingImage(
                            data: data,
                            destinationURL: droppedImageURL(pathExtension: ext)
                        )
                    )
                    break
                }
            }
            guard !images.isEmpty else { return false }

            onPromiseDropStarted()
            let writer = Self.imageWriter { [self] urls, errorDescriptions in
                defer { onPromiseDropFinished() }
                for errorDescription in errorDescriptions {
                    Log.shelf.error(
                        "Failed to materialize dropped image: \(errorDescription, privacy: .private)"
                    )
                }
                guard !urls.isEmpty else {
                    ShelfFeedback.rejectedDrop()
                    return
                }
                onDrop(urls.map { FileEntry(url: $0, isMaterializedByNab: true) })
            }
            let pendingImages = images
            imageWriteQueue.addOperation {
                writer(pendingImages)
            }
            return true
        }

        private func receiveFilePromises(from pasteboard: NSPasteboard) -> Bool {
            let receivers =
                pasteboard.readObjects(
                    forClasses: [NSFilePromiseReceiver.self],
                    options: nil
                ) as? [NSFilePromiseReceiver] ?? []
            guard !receivers.isEmpty else { return false }

            let destination: URL
            do {
                destination = try materializedFileStore.createPromisedFileDirectory()
            } catch {
                Log.shelf.error(
                    "Failed to prepare promised-file drop: \(error.localizedDescription, privacy: .private)"
                )
                return false
            }

            let dropID = UUID()
            let receiverIDs = receivers.map { _ in UUID() }
            promiseDrops[dropID] = PromiseDrop(
                receivers: receivers,
                destinationURL: destination,
                pendingReceiverIDs: Set(receiverIDs)
            )
            onPromiseDropStarted()
            for (receiver, receiverID) in zip(receivers, receiverIDs) {
                let reader = Self.filePromiseReader { [weak self] fileURL, error in
                    self?.promisedFileDidArrive(
                        fileURL,
                        error: error,
                        for: dropID,
                        receiverID: receiverID
                    )
                }
                receiver.receivePromisedFiles(
                    atDestination: destination,
                    options: [:],
                    operationQueue: filePromiseQueue,
                    reader: reader
                )
            }
            return true
        }

        static nonisolated func filePromiseReader(
            _ action: @escaping @MainActor @Sendable (URL, Error?) -> Void
        ) -> @Sendable (URL, Error?) -> Void {
            { fileURL, error in
                Task { @MainActor in
                    action(fileURL, error)
                }
            }
        }

        static nonisolated func imageWriter(
            _ action: @escaping @MainActor @Sendable ([URL], [String]) -> Void
        ) -> @Sendable ([PendingImage]) -> Void {
            { images in
                var writtenURLs: [URL] = []
                var errorDescriptions: [String] = []
                for image in images {
                    do {
                        try FileManager.default.createDirectory(
                            at: image.destinationURL.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try image.data.write(to: image.destinationURL, options: .atomic)
                        writtenURLs.append(image.destinationURL)
                    } catch {
                        errorDescriptions.append(error.localizedDescription)
                    }
                }
                Task { @MainActor in
                    action(writtenURLs, errorDescriptions)
                }
            }
        }

        private func promisedFileDidArrive(
            _ fileURL: URL,
            error: Error?,
            for dropID: UUID,
            receiverID: UUID
        ) {
            let entry: FileEntry?
            if let error {
                Log.shelf.error(
                    "Failed to receive promised file: \(error.localizedDescription, privacy: .private)"
                )
                entry = nil
            } else if FileManager.default.fileExists(atPath: fileURL.path) {
                entry = FileEntry(url: fileURL, isMaterializedByNab: true)
            } else {
                Log.shelf.error(
                    "Promised file is missing at \(fileURL.path, privacy: .private(mask: .hash))"
                )
                entry = nil
            }

            guard var drop = promiseDrops[dropID] else {
                if let entry {
                    onDrop([entry])
                }
                return
            }
            drop.pendingReceiverIDs.remove(receiverID)
            if let entry {
                drop.entries.append(entry)
            }

            if !drop.pendingReceiverIDs.isEmpty {
                promiseDrops[dropID] = drop
                return
            }

            promiseDrops.removeValue(forKey: dropID)
            if drop.entries.isEmpty {
                materializedFileStore.moveToTrash([drop.destinationURL])
                ShelfFeedback.rejectedDrop()
            } else {
                onDrop(drop.entries)
            }
            onPromiseDropFinished()
        }

        private func droppedImageURL(pathExtension: String) -> URL {
            let filename =
                "Screenshot \(Self.screenshotFormatter.string(from: Date()))-\(UUID().uuidString).\(pathExtension)"
            return materializedFileStore.droppedImageURL(filename: filename)
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

    }
}
