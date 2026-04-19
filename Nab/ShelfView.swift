import SwiftUI
import AppKit
import QuickLookThumbnailing

struct ShelfView: View {
    @Bindable var model: ShelfModel
    var onDropReceived: () -> Void = {}
    var onItemDragEnded: () -> Void = {}

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
        .dropDestination(for: URL.self) { (urls: [URL], _) -> Bool in
            handleDrop(urls: urls)
        }
    }

    private func handleDrop(urls: [URL]) -> Bool {
        let files = urls.filter { $0.isFileURL }
        guard !files.isEmpty else { return false }
        let result = model.add(files)
        if result.added == 0 && result.duplicates > 0 {
            NSAnimationEffect.poof.show(
                centeredAt: NSEvent.mouseLocation,
                size: NSSize(width: 32, height: 32)
            )
        }
        onDropReceived()
        return true
    }

    private var header: some View {
        HStack {
            Text("Nab")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
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
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 60), spacing: 8)],
                    alignment: .center,
                    spacing: 8
                ) {
                    ForEach(model.items) { item in
                        ShelfIcon(
                            item: item,
                            resolveURL: { model.resolveURL(for: item.id) },
                            onRemove: { model.remove(item.id) },
                            onDragEnded: onItemDragEnded
                        )
                    }
                }
                .padding(8)
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

    private static let iconSize: CGFloat = 48

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                FileDragSource(
                    resolveURL: resolveURL,
                    dragImage: thumbnail,
                    onMoved: onRemove,
                    onMissing: onRemove,
                    onDragEnded: onDragEnded
                ) {
                    Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: Self.iconSize, height: Self.iconSize)
                }
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
                .font(.system(size: 10))
                .lineLimit(2)
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

private struct FileDragSource<Content: View>: NSViewRepresentable {
    let resolveURL: () -> URL?
    let dragImage: NSImage?
    let onMoved: () -> Void
    let onMissing: () -> Void
    let onDragEnded: () -> Void
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
        (nsView.hostingView as? NSHostingView<Content>)?.rootView = content()
    }
}

private final class FileDragSourceView: NSView, NSDraggingSource {
    var resolveURL: () -> URL? = { nil }
    var dragImage: NSImage?
    var onMoved: () -> Void = {}
    var onMissing: () -> Void = {}
    var onDragEnded: () -> Void = {}
    weak var hostingView: NSView?

    private var mouseDownLocation: NSPoint?
    private static let dragThreshold: CGFloat = 3

    override var intrinsicContentSize: NSSize {
        hostingView?.intrinsicContentSize ?? super.intrinsicContentSize
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
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
              let primary = NSScreen.screens.first else { return false }
        let cgY = primary.frame.maxY - screenPoint.y
        for info in infos {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
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
