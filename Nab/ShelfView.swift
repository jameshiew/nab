import SwiftUI
import AppKit
import QuickLookThumbnailing
import QuickLookUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @Bindable var model: ShelfModel
    var onDropReceived: () -> Void = {}
    var onItemDragEnded: () -> Void = {}
    var onHeaderDragEnded: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
        .background(ShelfDropTarget(onDrop: handleDrop))
    }

    private func handleDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let result = model.add(urls)
        if result.added == 0 && result.duplicates > 0 {
            NSAnimationEffect.poof.show(
                centeredAt: NSEvent.mouseLocation,
                size: NSSize(width: 32, height: 32)
            )
        }
        onDropReceived()
    }

    private var header: some View {
        HStack {
            Text("Nab")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)
            Spacer()
            if !model.items.isEmpty {
                Button(action: model.clear) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Clear all")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(WindowDragHandle(onDragEnded: onHeaderDragEnded))
    }

    @ViewBuilder
    private var content: some View {
        if model.items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Drop files here")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.items) { item in
                        ShelfIcon(
                            item: item,
                            resolveURL: { model.resolveURL(for: item.id) },
                            onRemove: { model.remove(item.id) },
                            onDragEnded: onItemDragEnded
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
    }
}

private struct ShelfIcon: View {
    let item: ShelfItem
    let resolveURL: () -> URL?
    let onRemove: () -> Void
    let onDragEnded: () -> Void
    @State private var hovering = false
    @State private var thumbnail: NSImage?

    private static let iconSize: CGFloat = 96

    var body: some View {
        VStack(spacing: 6) {
            FileDragSource(
                resolveURL: resolveURL,
                dragImage: thumbnail,
                onMoved: onRemove,
                onMissing: onRemove,
                onDragEnded: onDragEnded,
                onQuickLook: quickLook
            ) {
                Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Self.iconSize, height: Self.iconSize)
            }
            .overlay(alignment: .topLeading) {
                if hovering {
                    Button(action: quickLook) {
                        Image(systemName: "eye.circle.fill")
                            .font(.system(size: 14))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Quick Look")
                    .offset(x: -4, y: -4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if hovering {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Remove")
                    .offset(x: 4, y: -4)
                }
            }
            Text(item.displayName)
                .font(.system(size: 12))
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hovering ? .white.opacity(0.08) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .task(id: item.url) {
            await loadThumbnail()
        }
    }

    private func quickLook() {
        guard let url = resolveURL() else {
            onRemove()
            return
        }
        QuickLookCoordinator.shared.preview(url: url)
    }

    private func loadThumbnail() async {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: Self.iconSize, height: Self.iconSize),
            scale: scale,
            representationTypes: .thumbnail
        )
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            thumbnail = rep.nsImage
        }
    }
}

private struct WindowDragHandle: NSViewRepresentable {
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
            NabLog.write("mouseDown origin=\(window.frame.origin)")
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window, let sm = startMouse, let so = startOrigin else { return }
            let m = NSEvent.mouseLocation
            window.setFrameOrigin(NSPoint(x: so.x + m.x - sm.x, y: so.y + m.y - sm.y))
            didDrag = true
        }

        override func mouseUp(with event: NSEvent) {
            NabLog.write("mouseUp didDrag=\(didDrag) origin=\(window?.frame.origin ?? .zero)")
            if didDrag { onDragEnded() }
            startMouse = nil
            startOrigin = nil
            didDrag = false
        }
    }
}

private struct FileDragSource<Content: View>: NSViewRepresentable {
    let resolveURL: () -> URL?
    let dragImage: NSImage?
    let onMoved: () -> Void
    let onMissing: () -> Void
    let onDragEnded: () -> Void
    let onQuickLook: () -> Void
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> FileDragSourceView {
        let host = NSHostingView(rootView: content())
        host.translatesAutoresizingMaskIntoConstraints = false
        let view = FileDragSourceView()
        view.resolveURL = resolveURL
        view.dragImage = dragImage
        view.onMoved = onMoved
        view.onMissing = onMissing
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
        nsView.resolveURL = resolveURL
        nsView.dragImage = dragImage
        nsView.onMoved = onMoved
        nsView.onMissing = onMissing
        nsView.onDragEnded = onDragEnded
        nsView.onQuickLook = onQuickLook
        (nsView.hostingView as? NSHostingView<Content>)?.rootView = content()
    }
}

private final class FileDragSourceView: NSView, NSDraggingSource {
    var resolveURL: () -> URL? = { nil }
    var dragImage: NSImage?
    var onMoved: () -> Void = {}
    var onMissing: () -> Void = {}
    var onDragEnded: () -> Void = {}
    var onQuickLook: () -> Void = {}
    weak var hostingView: NSView?

    private var mouseDownLocation: NSPoint?
    private var cursorInsideShelf = true
    private var didForceClick = false
    private static let dragThreshold: CGFloat = 3

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        pressureConfiguration = NSPressureConfiguration(pressureBehavior: .primaryDeepClick)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        hostingView?.intrinsicContentSize ?? super.intrinsicContentSize
    }

    override func mouseDown(with event: NSEvent) {
        NabLog.write("FileDragSource mouseDown clickCount=\(event.clickCount)")
        didForceClick = false
        if event.clickCount == 2 {
            mouseDownLocation = nil
            guard let url = resolveURL() else {
                onMissing()
                return
            }
            NabLog.write("FileDragSource opening \(url.path)")
            NSWorkspace.shared.open(url)
            return
        }
        mouseDownLocation = event.locationInWindow
    }

    override func pressureChange(with event: NSEvent) {
        guard !didForceClick, event.stage >= 2 else { return }
        didForceClick = true
        mouseDownLocation = nil
        NabLog.write("FileDragSource force click")
        onQuickLook()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let dx = event.locationInWindow.x - start.x
        let dy = event.locationInWindow.y - start.y
        guard hypot(dx, dy) > Self.dragThreshold else { return }
        mouseDownLocation = nil
        startDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        NabLog.write("FileDragSource mouseUp clickCount=\(event.clickCount)")
        mouseDownLocation = nil
    }

    private func startDrag(with event: NSEvent) {
        guard let url = resolveURL() else {
            NSAnimationEffect.poof.show(
                centeredAt: NSEvent.mouseLocation,
                size: NSSize(width: 32, height: 32)
            )
            onMissing()
            onDragEnded()
            return
        }
        let dragSize: CGFloat = 48
        let image: NSImage = {
            if let dragImage, let copy = dragImage.copy() as? NSImage {
                copy.size = NSSize(width: dragSize, height: dragSize)
                return copy
            }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: dragSize, height: dragSize)
            return icon
        }()
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let location = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(
            NSRect(
                x: location.x - dragSize / 2,
                y: location.y - dragSize / 2,
                width: dragSize,
                height: dragSize
            ),
            contents: image
        )
        cursorInsideShelf = true
        beginDraggingSession(with: [item], event: event, source: self)
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
            onMoved()
        }
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

/// NSView-based drop target. Reads the raw drag pasteboard so we can see
/// `public.file-url` even when a dragged item also exposes image data — SwiftUI's
/// `.onDrop(of:)` filters the NSItemProvider to the most specific accepted type
/// and strips the file URL for items like PNG files from Finder.
private struct ShelfDropTarget: NSViewRepresentable {
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
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let filename = "Screenshot \(formatter.string(from: Date())).\(ext)"
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

@MainActor
final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookCoordinator()
    private var urls: [URL] = []

    func preview(url: URL) {
        urls = [url]
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls[index] as NSURL
    }
}
