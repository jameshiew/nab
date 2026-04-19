import AppKit
import QuickLookThumbnailing
import SwiftUI

struct ShelfIcon: View {
    let item: ShelfItem
    let model: ShelfModel
    let onDragEnded: () -> Void
    @State private var hovering = false
    @State private var thumbnail: NSImage?

    private static let iconSize: CGFloat = 96

    var body: some View {
        let isSelected = model.isSelected(item.id)
        VStack(spacing: 6) {
            FileDragSource(
                itemID: item.id,
                model: model,
                dragImage: thumbnail,
                onDragEnded: onDragEnded,
                onQuickLook: quickLook
            ) {
                HStack(spacing: 0) {
                    Color.clear.frame(maxWidth: .infinity)
                    Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: Self.iconSize, height: Self.iconSize)
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .overlay { hoverActions }
                }
                .frame(height: Self.iconSize)
            }
            .frame(maxWidth: .infinity)
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
                .fill((isSelected || hovering) ? .white.opacity(0.08) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .task(id: item.url) {
            await loadThumbnail()
        }
    }

    private var hoverActions: some View {
        VStack(spacing: 10) {
            Button {
                model.remove(item.id)
            } label: {
                iconGlyph("xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .help("Remove")

            Button(action: quickLook) {
                iconGlyph("eye.circle.fill")
            }
            .buttonStyle(.plain)
            .help("Quick Look")
        }
        .opacity(hovering ? 1 : 0)
    }

    private func iconGlyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 24))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .black.opacity(0.6))
    }

    private func quickLook() {
        guard let url = model.resolveURL(for: item.id) else {
            model.remove(item.id)
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
