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

struct InboundDropFailure: Equatable, Sendable {
    let errorDescription: String
}

struct InboundDropResult: Equatable {
    let successfulEntries: [FileEntry]
    let failures: [InboundDropFailure]

    init(
        successfulEntries: [FileEntry],
        failures: [InboundDropFailure] = []
    ) {
        self.successfulEntries = successfulEntries
        self.failures = failures
    }

    var partialFailureMessage: String? {
        guard !successfulEntries.isEmpty, !failures.isEmpty else { return nil }
        let successfulCount = successfulEntries.count
        let totalCount = successfulCount + failures.count
        let verb = successfulCount == 1 ? "was" : "were"
        return
            "\(successfulCount) of \(totalCount) files \(verb) parked; \(failures.count) failed."
    }
}

struct DropPasteboardInterpreter {
    typealias DiagnosticEvent = (_ name: String, _ details: [String: String]) -> Void

    enum Plan {
        case filePromise(NSFilePromiseReceiver)
        case fileURL(URL)
        case image(PendingImage)
    }

    struct PendingImage: Sendable {
        let data: Data
        let destinationURL: URL
    }

    static let supportedImageTypes: [(NSPasteboard.PasteboardType, String)] = [
        (NSPasteboard.PasteboardType(UTType.png.identifier), "png"),
        (NSPasteboard.PasteboardType(UTType.jpeg.identifier), "jpg"),
        (NSPasteboard.PasteboardType(UTType.heic.identifier), "heic"),
        (NSPasteboard.PasteboardType(UTType.tiff.identifier), "tiff"),
        (NSPasteboard.PasteboardType(UTType.gif.identifier), "gif"),
    ]

    let imageDestinationURL: (String) -> URL
    let recordDiagnosticEvent: DiagnosticEvent

    init(
        imageDestinationURL: @escaping (String) -> URL,
        recordDiagnosticEvent: @escaping DiagnosticEvent = { _, _ in }
    ) {
        self.imageDestinationURL = imageDestinationURL
        self.recordDiagnosticEvent = recordDiagnosticEvent
    }

    func plans(from pasteboard: NSPasteboard) -> [Plan] {
        let items = pasteboard.pasteboardItems ?? []
        let promiseReceivers =
            pasteboard.readObjects(
                forClasses: [NSFilePromiseReceiver.self],
                options: nil
            ) as? [NSFilePromiseReceiver] ?? []
        var promiseReceiverIndex = 0
        var plans: [Plan] = []
        for (index, item) in items.enumerated() {
            var itemWasPlanned = false
            let itemDetails = [
                "item_index": String(index),
                "types": item.types.map(\.rawValue).sorted().joined(separator: ","),
            ]
            recordDiagnosticEvent("drop_item_inspection_started", itemDetails)

            if Self.hasFilePromiseRepresentation(item),
                promiseReceivers.indices.contains(promiseReceiverIndex)
            {
                let receiver = promiseReceivers[promiseReceiverIndex]
                promiseReceiverIndex += 1
                recordDiagnosticEvent(
                    "drop_item_planned_as_file_promise",
                    itemDetails.merging([
                        "advertised_file_count": String(receiver.fileNames.count),
                        "advertised_type_count": String(receiver.fileTypes.count),
                    ]) { _, new in new }
                )
                plans.append(.filePromise(receiver))
                itemWasPlanned = true
                continue
            }
            recordDiagnosticEvent("drop_item_file_promise_absent", itemDetails)

            if let url = Self.fileURL(from: item) {
                recordDiagnosticEvent("drop_item_planned_as_file_url", itemDetails)
                plans.append(.fileURL(url))
                itemWasPlanned = true
                continue
            }
            recordDiagnosticEvent("drop_item_file_url_absent", itemDetails)

            for (type, ext) in Self.supportedImageTypes where item.types.contains(type) {
                recordDiagnosticEvent(
                    "drop_item_image_read_started",
                    itemDetails.merging(["image_type": type.rawValue]) { _, new in new }
                )
                guard let data = item.data(forType: type) else {
                    recordDiagnosticEvent(
                        "drop_item_image_read_returned_no_data",
                        itemDetails.merging(["image_type": type.rawValue]) { _, new in new }
                    )
                    continue
                }
                recordDiagnosticEvent(
                    "drop_item_planned_as_image",
                    itemDetails.merging([
                        "byte_count": String(data.count),
                        "image_type": type.rawValue,
                    ]) { _, new in new }
                )
                plans.append(
                    .image(
                        PendingImage(
                            data: data,
                            destinationURL: imageDestinationURL(ext)
                        )
                    )
                )
                itemWasPlanned = true
                break
            }
            if !itemWasPlanned {
                recordDiagnosticEvent("drop_item_unsupported", itemDetails)
            }
        }
        return plans
    }

    private static func hasFilePromiseRepresentation(_ item: NSPasteboardItem) -> Bool {
        let readableTypes = Set(
            NSFilePromiseReceiver.readableDraggedTypes.map {
                NSPasteboard.PasteboardType($0)
            }
        )
        return !readableTypes.isDisjoint(with: item.types)
    }

    private static func fileURL(from item: NSPasteboardItem) -> URL? {
        guard let value = item.string(forType: .fileURL),
            let url = URL(string: value),
            url.isFileURL,
            FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }
}

struct PromiseDropAccumulator {
    private struct ReceivedFile {
        let fileIndex: Int?
        let entry: FileEntry?
        let failure: InboundDropFailure?
    }

    private struct ReceiverState {
        var fileNames: [String] = []
        var expectedFileCount = 1
        var receivedFiles: [ReceivedFile] = []
        var claimedFileIndices: Set<Int> = []

        var isComplete: Bool {
            receivedFiles.count >= expectedFileCount
        }
    }

    private var receivers: [ReceiverState]

    init(receiverCount: Int) {
        receivers = (0..<receiverCount).map { _ in ReceiverState() }
    }

    mutating func configureReceiver(
        at receiverIndex: Int,
        fileNames: [String],
        fileTypeCount: Int
    ) {
        precondition(receivers.indices.contains(receiverIndex))
        precondition(receivers[receiverIndex].receivedFiles.isEmpty)
        receivers[receiverIndex].fileNames = fileNames
        receivers[receiverIndex].expectedFileCount = max(
            fileNames.count,
            fileTypeCount,
            1
        )
    }

    @discardableResult
    mutating func record(
        _ entry: FileEntry,
        fileURL: URL,
        for receiverIndex: Int
    ) -> Bool {
        record(
            entry: entry,
            failure: nil,
            fileURL: fileURL,
            for: receiverIndex
        )
    }

    @discardableResult
    mutating func recordFailure(
        _ failure: InboundDropFailure,
        fileURL: URL,
        for receiverIndex: Int
    ) -> Bool {
        record(
            entry: nil,
            failure: failure,
            fileURL: fileURL,
            for: receiverIndex
        )
    }

    private mutating func record(
        entry: FileEntry?,
        failure: InboundDropFailure?,
        fileURL: URL,
        for receiverIndex: Int
    ) -> Bool {
        precondition(receivers.indices.contains(receiverIndex))
        precondition((entry == nil) != (failure == nil))
        var receiver = receivers[receiverIndex]
        let wasExpected = receiver.receivedFiles.count < receiver.expectedFileCount
        if !wasExpected {
            receiver.expectedFileCount += 1
        }

        let fileIndex: Int?
        if entry != nil,
            let index = receiver.fileNames.indices.first(where: {
                !receiver.claimedFileIndices.contains($0)
                    && receiver.fileNames[$0] == fileURL.lastPathComponent
            })
        {
            receiver.claimedFileIndices.insert(index)
            fileIndex = index
        } else {
            fileIndex = nil
        }
        receiver.receivedFiles.append(
            ReceivedFile(fileIndex: fileIndex, entry: entry, failure: failure)
        )
        receivers[receiverIndex] = receiver
        return wasExpected
    }

    var isComplete: Bool {
        receivers.allSatisfy(\.isComplete)
    }

    var result: InboundDropResult {
        let successfulEntries = receivers.flatMap { receiver in
            var entries = [FileEntry?](
                repeating: nil,
                count: receiver.expectedFileCount
            )
            var unmatchedEntries: [FileEntry] = []
            for receivedFile in receiver.receivedFiles {
                guard let entry = receivedFile.entry else { continue }
                if let fileIndex = receivedFile.fileIndex,
                    entries.indices.contains(fileIndex),
                    entries[fileIndex] == nil
                {
                    entries[fileIndex] = entry
                } else {
                    unmatchedEntries.append(entry)
                }
            }
            for entry in unmatchedEntries {
                if let index = entries.firstIndex(where: { $0 == nil }) {
                    entries[index] = entry
                } else {
                    entries.append(entry)
                }
            }
            return entries.compactMap { $0 }
        }
        let failures = receivers.flatMap { receiver in
            receiver.receivedFiles.compactMap(\.failure)
        }
        return InboundDropResult(
            successfulEntries: successfulEntries,
            failures: failures
        )
    }
}

struct LegacyEmailPromiseMonitor {
    private struct FileState: Equatable {
        let url: URL
        let fileSize: Int?
        let modificationDate: Date?
    }

    let expectedFileNames: [String]
    let expectedFileCount: Int
    private var previousState: [FileState]?

    init(expectedFileNames: [String], fallbackExpectedFileCount: Int) {
        self.expectedFileNames = expectedFileNames
        expectedFileCount = max(expectedFileNames.count, fallbackExpectedFileCount, 1)
    }

    mutating func completedURLs(in destinationURL: URL) -> [URL]? {
        let manager = FileManager.default
        guard
            let contents = try? manager.contentsOfDirectory(
                at: destinationURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
            )
        else { return nil }

        let emailURLs = contents.filter { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .emailMessage)
        }
        guard emailURLs.count >= expectedFileCount else { return nil }

        var claimedURLs: Set<URL> = []
        let expectedURLs = expectedFileNames.compactMap { name -> URL? in
            guard
                let match = emailURLs.first(where: {
                    !claimedURLs.contains($0)
                        && $0.lastPathComponent == URL(fileURLWithPath: name).lastPathComponent
                })
            else { return nil }
            claimedURLs.insert(match)
            return match
        }
        let remainingURLs =
            emailURLs
            .filter { !claimedURLs.contains($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let orderedURLs = expectedURLs + remainingURLs
        let currentState = orderedURLs.map { url in
            let values = try? url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
            ])
            return FileState(
                url: url,
                fileSize: values?.fileSize,
                modificationDate: values?.contentModificationDate
            )
        }
        defer { previousState = currentState }
        return currentState == previousState ? orderedURLs : nil
    }
}

/// NSView-based drop target. Reads the raw drag pasteboard so we can see
/// `public.file-url` even when a dragged item also exposes image data — SwiftUI's
/// `.onDrop(of:)` filters the NSItemProvider to the most specific accepted type
/// and strips the file URL for items like PNG files from Finder.
struct ShelfDropTarget: NSViewRepresentable {
    let materializedFileStore: MaterializedFileStore
    let onDrop: (InboundDropResult) -> Void
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
        var onDrop: (InboundDropResult) -> Void = { _ in }
        var onPromiseDropStarted: () -> Void = {}
        var onPromiseDropFinished: () -> Void = {}

        private struct PromiseDrop {
            let receivers: [NSFilePromiseReceiver]
            let destinationURL: URL
            var state: PromiseDropAccumulator
        }

        struct ImageWriteResult: Equatable, Sendable {
            let successfulURLs: [URL]
            let failures: [InboundDropFailure]
        }

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
        private var legacyEmailPromiseTasks: [UUID: Task<Void, Never>] = [:]

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            var types = NSFilePromiseReceiver.readableDraggedTypes.map {
                NSPasteboard.PasteboardType($0)
            }
            types.append(.fileURL)
            types.append(contentsOf: DropPasteboardInterpreter.supportedImageTypes.map(\.0))
            registerForDraggedTypes(types)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            let operation = Self.dragOperation(forSource: sender.draggingSource)
            DiagnosticsRecorder.shared.record(
                "drop_dragging_entered",
                details: [
                    "accepted": String(!operation.isEmpty),
                    "pasteboard_item_count": String(
                        sender.draggingPasteboard.pasteboardItems?.count ?? 0
                    ),
                ]
            )
            return operation
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            Self.dragOperation(forSource: sender.draggingSource)
        }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let accepted = !Self.dragOperation(forSource: sender.draggingSource).isEmpty
            DiagnosticsRecorder.shared.record(
                "drop_preparation_finished",
                details: ["accepted": String(accepted)]
            )
            return accepted
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let dropID = UUID()
            let diagnosticDropID = dropID.uuidString.lowercased()
            guard !Self.dragOperation(forSource: sender.draggingSource).isEmpty else {
                DiagnosticsRecorder.shared.record(
                    "drop_rejected_as_internal",
                    details: ["drop_id": diagnosticDropID]
                )
                ShelfFeedback.rejectedDrop()
                return false
            }

            let pasteboard = sender.draggingPasteboard
            DiagnosticsRecorder.shared.record(
                "drop_perform_started",
                details: [
                    "change_count": String(pasteboard.changeCount),
                    "drop_id": diagnosticDropID,
                    "pasteboard_item_count": String(pasteboard.pasteboardItems?.count ?? 0),
                ]
            )
            let interpreter = DropPasteboardInterpreter(
                imageDestinationURL: droppedImageURL(pathExtension:),
                recordDiagnosticEvent: { name, details in
                    DiagnosticsRecorder.shared.record(
                        name,
                        details: details.merging(["drop_id": diagnosticDropID]) { _, new in new }
                    )
                }
            )
            let plans = interpreter.plans(from: pasteboard)
            guard !plans.isEmpty else {
                DiagnosticsRecorder.shared.record(
                    "drop_finished_without_supported_items",
                    details: ["drop_id": diagnosticDropID]
                )
                return false
            }

            var receivers: [NSFilePromiseReceiver] = []
            var entries: [FileEntry] = []
            var images: [DropPasteboardInterpreter.PendingImage] = []
            for plan in plans {
                switch plan {
                case .filePromise(let receiver):
                    receivers.append(receiver)
                case .fileURL(let url):
                    entries.append(FileEntry(url: url))
                case .image(let image):
                    images.append(image)
                }
            }
            DiagnosticsRecorder.shared.record(
                "drop_plans_ready",
                details: [
                    "direct_file_count": String(entries.count),
                    "drop_id": diagnosticDropID,
                    "image_count": String(images.count),
                    "promise_count": String(receivers.count),
                ]
            )

            let receivesEmailThroughLegacyPromise = receivers.contains {
                Self.requiresLegacyEmailPromise(forFileTypes: $0.fileTypes)
            }
            var accepted =
                receivesEmailThroughLegacyPromise
                ? receiveLegacyEmailPromises(
                    from: sender,
                    fallbackExpectedFileCount: receivers.count,
                    dropID: dropID
                )
                : receiveFilePromises(receivers, dropID: dropID)
            if !entries.isEmpty {
                DiagnosticsRecorder.shared.record(
                    "drop_direct_files_delivery_started",
                    details: [
                        "drop_id": diagnosticDropID,
                        "entry_count": String(entries.count),
                    ]
                )
                onDrop(InboundDropResult(successfulEntries: entries))
                DiagnosticsRecorder.shared.record(
                    "drop_direct_files_delivery_finished",
                    details: ["drop_id": diagnosticDropID]
                )
                accepted = true
            }
            accepted = receiveImages(images, dropID: dropID) || accepted
            DiagnosticsRecorder.shared.record(
                "drop_perform_finished",
                details: [
                    "accepted": String(accepted),
                    "drop_id": diagnosticDropID,
                ]
            )
            return accepted
        }

        static func dragOperation(forSource source: Any?) -> NSDragOperation {
            source is FileDragSourceView ? [] : .copy
        }

        static func requiresLegacyEmailPromise(forFileTypes fileTypes: [String]) -> Bool {
            fileTypes.contains { rawType in
                UTType(rawType)?.conforms(to: .emailMessage) == true
            }
        }

        static func legacyPromisedFileNames(
            from source: AnyObject,
            at destinationURL: URL,
            selector: Selector = NSSelectorFromString(
                "namesOfPromisedFilesDroppedAtDestination:"
            )
        ) -> [String] {
            guard source.responds(to: selector),
                let result = source.perform(selector, with: destinationURL)
            else { return [] }
            return result.takeUnretainedValue() as? [String] ?? []
        }

        private func receiveLegacyEmailPromises(
            from sender: NSDraggingInfo,
            fallbackExpectedFileCount: Int,
            dropID: UUID
        ) -> Bool {
            let diagnosticDropID = dropID.uuidString.lowercased()
            let destinationURL: URL
            do {
                destinationURL = try materializedFileStore.createPromisedFileDirectory()
            } catch {
                DiagnosticsRecorder.shared.record(
                    "drop_legacy_email_promise_preparation_failed",
                    details: [
                        "drop_id": diagnosticDropID,
                        "error_type": String(reflecting: type(of: error)),
                    ]
                )
                return false
            }

            onPromiseDropStarted()
            let fileNames = Self.legacyPromisedFileNames(
                from: sender,
                at: destinationURL
            )
            DiagnosticsRecorder.shared.record(
                "drop_legacy_email_promise_monitoring_started",
                details: [
                    "drop_id": diagnosticDropID,
                    "expected_file_count": String(
                        max(fileNames.count, fallbackExpectedFileCount, 1)
                    ),
                    "returned_file_name_count": String(fileNames.count),
                ]
            )

            var monitor = LegacyEmailPromiseMonitor(
                expectedFileNames: fileNames,
                fallbackExpectedFileCount: fallbackExpectedFileCount
            )
            legacyEmailPromiseTasks[dropID] = Task { @MainActor [weak self] in
                let deadline = ContinuousClock.now + .seconds(60)
                while !Task.isCancelled, ContinuousClock.now < deadline {
                    if let urls = monitor.completedURLs(in: destinationURL) {
                        self?.finishLegacyEmailPromiseDrop(
                            dropID: dropID,
                            destinationURL: destinationURL,
                            urls: urls,
                            failure: nil
                        )
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard !Task.isCancelled else { return }
                self?.finishLegacyEmailPromiseDrop(
                    dropID: dropID,
                    destinationURL: destinationURL,
                    urls: [],
                    failure: InboundDropFailure(
                        errorDescription: "The promised email was not received."
                    )
                )
            }
            return true
        }

        private func finishLegacyEmailPromiseDrop(
            dropID: UUID,
            destinationURL: URL,
            urls: [URL],
            failure: InboundDropFailure?
        ) {
            legacyEmailPromiseTasks.removeValue(forKey: dropID)
            let failures = failure.map { [$0] } ?? []
            if urls.isEmpty {
                materializedFileStore.moveToTrash([destinationURL])
            }
            DiagnosticsRecorder.shared.record(
                "drop_legacy_email_promise_delivery_started",
                details: [
                    "drop_id": dropID.uuidString.lowercased(),
                    "failure_count": String(failures.count),
                    "success_count": String(urls.count),
                ]
            )
            onDrop(
                InboundDropResult(
                    successfulEntries: urls.map {
                        FileEntry(url: $0, isMaterializedByNab: true)
                    },
                    failures: failures
                )
            )
            onPromiseDropFinished()
        }

        private func receiveImages(
            _ images: [DropPasteboardInterpreter.PendingImage],
            dropID: UUID
        ) -> Bool {
            guard !images.isEmpty else { return false }

            let diagnosticDropID = dropID.uuidString.lowercased()
            DiagnosticsRecorder.shared.record(
                "drop_image_materialization_queued",
                details: [
                    "drop_id": diagnosticDropID,
                    "image_count": String(images.count),
                    "total_byte_count": String(images.reduce(0) { $0 + $1.data.count }),
                ]
            )
            onPromiseDropStarted()
            let writer = Self.imageWriter { [self] result in
                defer { onPromiseDropFinished() }
                DiagnosticsRecorder.shared.record(
                    "drop_image_materialization_finished",
                    details: [
                        "drop_id": diagnosticDropID,
                        "failure_count": String(result.failures.count),
                        "success_count": String(result.successfulURLs.count),
                    ]
                )
                for failure in result.failures {
                    Log.shelf.error(
                        "Failed to materialize dropped image: \(failure.errorDescription, privacy: .private)"
                    )
                }
                let entries = result.successfulURLs.map {
                    FileEntry(url: $0, isMaterializedByNab: true)
                }
                DiagnosticsRecorder.shared.record(
                    "drop_image_delivery_started",
                    details: [
                        "drop_id": diagnosticDropID,
                        "entry_count": String(entries.count),
                    ]
                )
                onDrop(
                    InboundDropResult(
                        successfulEntries: entries,
                        failures: result.failures
                    )
                )
                DiagnosticsRecorder.shared.record(
                    "drop_image_delivery_finished",
                    details: ["drop_id": diagnosticDropID]
                )
            }
            let pendingImages = images
            imageWriteQueue.addOperation {
                writer(pendingImages)
            }
            return true
        }

        private func receiveFilePromises(
            _ receivers: [NSFilePromiseReceiver],
            dropID: UUID
        ) -> Bool {
            guard !receivers.isEmpty else { return false }

            let diagnosticDropID = dropID.uuidString.lowercased()
            DiagnosticsRecorder.shared.record(
                "drop_file_promise_preparation_started",
                details: [
                    "drop_id": diagnosticDropID,
                    "receiver_count": String(receivers.count),
                ]
            )
            let destination: URL
            do {
                destination = try materializedFileStore.createPromisedFileDirectory()
            } catch {
                DiagnosticsRecorder.shared.record(
                    "drop_file_promise_preparation_failed",
                    details: [
                        "drop_id": diagnosticDropID,
                        "error_type": String(reflecting: type(of: error)),
                    ]
                )
                Log.shelf.error(
                    "Failed to prepare promised-file drop: \(error.localizedDescription, privacy: .private)"
                )
                return false
            }

            var state = PromiseDropAccumulator(receiverCount: receivers.count)
            onPromiseDropStarted()
            for (receiverIndex, receiver) in receivers.enumerated() {
                DiagnosticsRecorder.shared.record(
                    "drop_file_promise_receiver_started",
                    details: [
                        "advertised_file_count": String(receiver.fileNames.count),
                        "advertised_type_count": String(receiver.fileTypes.count),
                        "drop_id": diagnosticDropID,
                        "receiver_index": String(receiverIndex),
                    ]
                )
                let reader = Self.filePromiseReader { [weak self] fileURL, error in
                    self?.promisedFileDidArrive(
                        fileURL,
                        error: error,
                        for: dropID,
                        receiverIndex: receiverIndex
                    )
                }
                receiver.receivePromisedFiles(
                    atDestination: destination,
                    options: [:],
                    operationQueue: filePromiseQueue,
                    reader: reader
                )
                state.configureReceiver(
                    at: receiverIndex,
                    fileNames: receiver.fileNames,
                    fileTypeCount: receiver.fileTypes.count
                )
            }
            promiseDrops[dropID] = PromiseDrop(
                receivers: receivers,
                destinationURL: destination,
                state: state
            )
            DiagnosticsRecorder.shared.record(
                "drop_file_promise_callbacks_pending",
                details: ["drop_id": diagnosticDropID]
            )
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
            _ action: @escaping @MainActor @Sendable (ImageWriteResult) -> Void
        ) -> @Sendable ([DropPasteboardInterpreter.PendingImage]) -> Void {
            { images in
                var writtenURLs: [URL] = []
                var failures: [InboundDropFailure] = []
                for image in images {
                    do {
                        try FileManager.default.createDirectory(
                            at: image.destinationURL.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try image.data.write(to: image.destinationURL, options: .atomic)
                        writtenURLs.append(image.destinationURL)
                    } catch {
                        failures.append(
                            InboundDropFailure(errorDescription: error.localizedDescription)
                        )
                    }
                }
                let result = ImageWriteResult(
                    successfulURLs: writtenURLs,
                    failures: failures
                )
                Task { @MainActor in
                    action(result)
                }
            }
        }

        private func promisedFileDidArrive(
            _ fileURL: URL,
            error: Error?,
            for dropID: UUID,
            receiverIndex: Int
        ) {
            let diagnosticDropID = dropID.uuidString.lowercased()
            DiagnosticsRecorder.shared.record(
                "drop_file_promise_callback_started",
                details: [
                    "drop_id": diagnosticDropID,
                    "has_error": String(error != nil),
                    "receiver_index": String(receiverIndex),
                ]
            )
            let entry: FileEntry?
            let failure: InboundDropFailure?
            if let error {
                Log.shelf.error(
                    "Failed to receive promised file: \(error.localizedDescription, privacy: .private)"
                )
                entry = nil
                failure = InboundDropFailure(errorDescription: error.localizedDescription)
            } else if FileManager.default.fileExists(atPath: fileURL.path) {
                entry = FileEntry(url: fileURL, isMaterializedByNab: true)
                failure = nil
            } else {
                Log.shelf.error(
                    "Promised file is missing at \(fileURL.path, privacy: .private(mask: .hash))"
                )
                entry = nil
                failure = InboundDropFailure(
                    errorDescription: "The promised file was not received."
                )
            }

            guard var drop = promiseDrops[dropID] else {
                DiagnosticsRecorder.shared.record(
                    "drop_file_promise_callback_after_completion",
                    details: ["drop_id": diagnosticDropID]
                )
                Log.shelf.fault("Received a promised-file callback after its drop finished")
                if let entry {
                    onDrop(InboundDropResult(successfulEntries: [entry]))
                }
                return
            }
            let wasExpected: Bool
            switch (entry, failure) {
            case (.some(let entry), nil):
                wasExpected = drop.state.record(
                    entry,
                    fileURL: fileURL,
                    for: receiverIndex
                )
            case (nil, .some(let failure)):
                wasExpected = drop.state.recordFailure(
                    failure,
                    fileURL: fileURL,
                    for: receiverIndex
                )
            default:
                preconditionFailure("Promised-file callbacks require one result")
            }
            if !wasExpected {
                DiagnosticsRecorder.shared.record(
                    "drop_file_promise_unadvertised_callback",
                    details: ["drop_id": diagnosticDropID]
                )
                Log.shelf.fault("Received more promised files than the receiver advertised")
            }

            if !drop.state.isComplete {
                DiagnosticsRecorder.shared.record(
                    "drop_file_promise_callback_recorded",
                    details: [
                        "drop_id": diagnosticDropID,
                        "receiver_index": String(receiverIndex),
                    ]
                )
                promiseDrops[dropID] = drop
                return
            }

            promiseDrops.removeValue(forKey: dropID)
            let result = drop.state.result
            if result.successfulEntries.isEmpty {
                materializedFileStore.moveToTrash([drop.destinationURL])
            }
            DiagnosticsRecorder.shared.record(
                "drop_file_promise_delivery_started",
                details: [
                    "drop_id": diagnosticDropID,
                    "failure_count": String(result.failures.count),
                    "success_count": String(result.successfulEntries.count),
                ]
            )
            onDrop(result)
            DiagnosticsRecorder.shared.record(
                "drop_file_promise_delivery_finished",
                details: ["drop_id": diagnosticDropID]
            )
            onPromiseDropFinished()
        }

        private func droppedImageURL(pathExtension: String) -> URL {
            let filename =
                "Screenshot \(Self.screenshotFormatter.string(from: Date()))-\(UUID().uuidString).\(pathExtension)"
            return materializedFileStore.droppedImageURL(filename: filename)
        }
    }
}
