import AppKit
import SwiftUI

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
            emptyState
        } else {
            itemGrid
        }
    }

    private var emptyState: some View {
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
    }

    private var itemGrid: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(model.items) { item in
                    ShelfIcon(
                        item: item,
                        model: model,
                        onDragEnded: onItemDragEnded
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }
}
