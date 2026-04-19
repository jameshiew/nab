import AppKit
import SwiftUI

@MainActor
final class ShelfController {
    private let model = ShelfModel()
    private lazy var panel: ShelfPanel = {
        let view = ShelfView(model: model) { [weak self] in
            self?.handleDrop()
        }
        return ShelfPanel(rootView: view)
    }()
    private let dragMonitor = DragMonitor()
    private var hideTask: Task<Void, Never>?

    private static let postDragLinger: Duration = .seconds(1.5)

    func start() {
        dragMonitor.dragStarted = { [weak self] in self?.onDragStarted() }
        dragMonitor.dragEnded = { [weak self] in self?.onDragEnded() }
        dragMonitor.start()
        _ = panel
    }

    private func onDragStarted() {
        cancelHide()
        panel.slideIn()
    }

    private func onDragEnded() {
        if model.items.isEmpty {
            scheduleHide(after: .seconds(0.4))
        }
    }

    private func handleDrop() {
        cancelHide()
    }

    private func scheduleHide(after delay: Duration) {
        cancelHide()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            if self.model.items.isEmpty {
                self.panel.slideOut()
            }
        }
    }

    private func cancelHide() {
        hideTask?.cancel()
        hideTask = nil
    }
}
