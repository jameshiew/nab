import AppKit
import QuickLookThumbnailing
import SwiftUI

struct ShelfIcon: View {
    let item: ShelfItem
    let model: ShelfModel
    let exportCoordinator: FileExportCoordinator
    let onDragEnded: () -> Void
    @State private var hovering = false
    @State private var thumbnail: NSImage?

    private static let iconSize: CGFloat = 96
    private static let maxStackLayers = 3
    private static let stackOffset: CGFloat = 4
    /// Size of each layer in a stack, small enough that the most offset layer
    /// still fits within `iconSize` without intruding into adjacent views.
    private static var stackCardSize: CGFloat {
        iconSize - 2 * CGFloat(maxStackLayers - 1) * stackOffset
    }

    var body: some View {
        let isSelected = model.isSelected(item.id)
        VStack(spacing: 6) {
            FileDragSource(
                itemID: item.id,
                model: model,
                exportCoordinator: exportCoordinator,
                dragImage: thumbnail,
                onDragEnded: onDragEnded,
                onForceClick: item.isStack ? {} : quickLook
            ) {
                HStack(spacing: 0) {
                    Color.clear.frame(maxWidth: .infinity)
                    thumbnailStack
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
        .task(id: item.primaryURL) {
            await loadThumbnail()
        }
    }

    private var thumbnailStack: some View {
        ZStack(alignment: .bottomTrailing) {
            if item.isStack {
                stackedFileIcons
            } else {
                Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: item.primaryURL.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Self.iconSize, height: Self.iconSize)
            }
            if item.isStack {
                Text("\(item.entries.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.blue))
                    .padding(2)
            }
        }
    }

    /// Up to 3 generic file-type icons fanned up-right so the stack reads cleanly regardless of the files' actual aspect ratios.
    private var stackedFileIcons: some View {
        let layerCount = min(item.entries.count, Self.maxStackLayers)
        return ZStack {
            ForEach((0..<layerCount).reversed(), id: \.self) { idx in
                let offset = CGFloat(idx) * Self.stackOffset
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.entries[idx].url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Self.stackCardSize, height: Self.stackCardSize)
                    .offset(x: offset, y: -offset)
            }
        }
    }

    private var hoverActions: some View {
        VStack(spacing: 10) {
            ShelfActionButton(help: "Remove") {
                model.remove(item.id)
            } glyph: {
                Image(systemName: "xmark")
                    .font(.system(size: ShelfAction.glyphFontSize, weight: .semibold))
                    .foregroundStyle(.white)
            }

            if item.isStack {
                ShelfActionButton(help: "Split stack") {
                    model.split(item.id)
                } glyph: {
                    FanStackCards()
                        .frame(width: ShelfAction.glyphSize, height: ShelfAction.glyphSize)
                }
            } else {
                ShelfActionButton(help: "Quick Look", action: quickLook) {
                    Image(systemName: "eye")
                        .font(.system(size: ShelfAction.glyphFontSize, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .opacity(hovering ? 1 : 0)
    }

    private func quickLook() {
        let urls = model.resolveURLs(for: item.id)
        guard let url = urls.first else { return }
        QuickLookCoordinator.shared.preview(url: url)
    }

    private func loadThumbnail() async {
        // Stacks render generic file-type icons (cheap + synchronous), so a
        // rendered content thumbnail is only needed for single-file items.
        guard !item.isStack else {
            thumbnail = nil
            return
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let request = QLThumbnailGenerator.Request(
            fileAt: item.primaryURL,
            size: CGSize(width: Self.iconSize, height: Self.iconSize),
            scale: scale,
            representationTypes: .thumbnail
        )
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            guard !Task.isCancelled else { return }
            thumbnail = rep.nsImage
        } else if !Task.isCancelled {
            thumbnail = nil
        }
    }
}

/// Fixed sizes for hover action buttons. Living outside the generic button
/// type lets call sites reference them without having to spell out the
/// generic's `Glyph` parameter.
private enum ShelfAction {
    static let circleSize: CGFloat = 28
    /// Side length of the square region a glyph draws into.
    static let glyphSize: CGFloat = 16
    /// Font size for SF Symbol glyphs — tuned to visually match `glyphSize`.
    static let glyphFontSize: CGFloat = 15
}

/// Circular hover action button with a fixed-size dark backing circle and a
/// white glyph inside. Any view (SF Symbol image or a custom shape) can be
/// supplied as the glyph, giving all hover actions consistent sizing without
/// depending on SF Symbols' own glyph-to-font-size ratio.
private struct ShelfActionButton<Glyph: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder let glyph: () -> Glyph

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(.black.opacity(0.6))
                glyph()
                    .frame(width: ShelfAction.glyphSize, height: ShelfAction.glyphSize)
            }
            .frame(width: ShelfAction.circleSize, height: ShelfAction.circleSize)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Fan-of-three-cards glyph drawn from SwiftUI shapes — reads as "un-stack".
/// Scales to whatever frame it's given; stroke width and corner radius scale
/// in proportion so the icon stays legible at small sizes.
private struct FanStackCards: View {
    // Geometry matches a 64x64 viewBox (card 20x26, pivot below cards), then
    // every dimension is multiplied by the rendered size.
    private static let viewBox: CGFloat = 64
    private static let cardW: CGFloat = 20
    private static let cardH: CGFloat = 26
    private static let cardCenterY: CGFloat = 25
    private static let pivotY: CGFloat = 50
    private static let fanAngle: Double = 18
    private static let cornerRadius: CGFloat = 2
    private static let strokeWidth: CGFloat = 3.5

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / Self.viewBox
            ZStack {
                fanCard(angle: -Self.fanAngle, scale: s)
                fanCard(angle: Self.fanAngle, scale: s)
                cardShape(filled: true, scale: s)
                    .frame(width: Self.cardW * s, height: Self.cardH * s)
                    .position(x: geo.size.width / 2, y: Self.cardCenterY * s)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func fanCard(angle: Double, scale: CGFloat) -> some View {
        cardShape(filled: false, scale: scale)
            .frame(width: Self.cardW * scale, height: Self.cardH * scale)
            .position(x: Self.viewBox * scale / 2, y: Self.cardCenterY * scale)
            .rotationEffect(
                .degrees(angle),
                anchor: UnitPoint(x: 0.5, y: Self.pivotY / Self.viewBox)
            )
    }

    private func cardShape(filled: Bool, scale: CGFloat) -> some View {
        let r = Self.cornerRadius * scale
        let lw = max(0.8, Self.strokeWidth * scale)
        return RoundedRectangle(cornerRadius: r, style: .continuous)
            .fill(filled ? Color.white : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .stroke(Color.white, lineWidth: lw)
            )
    }
}
