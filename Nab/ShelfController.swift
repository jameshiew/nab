import AppKit
import SwiftUI

@MainActor
final class ShelfController {
    private let model = ShelfModel()
    private lazy var panel: ShelfPanel = {
        let view = ShelfView(
            model: model,
            onDropReceived: { [weak self] in self?.handleDrop() },
            onItemDragEnded: { [weak self] in self?.dragMonitor.endOwnDrag() }
        )
        return ShelfPanel(rootView: view)
    }()
    private let dragMonitor = DragMonitor()
    private var hideTask: Task<Void, Never>?
    private var inDrag = false

    private static let emptyHideDelay: Duration = .milliseconds(400)

    func start() {
        dragMonitor.dragStarted = { [weak self] in self?.onDragStarted() }
        dragMonitor.dragEnded = { [weak self] in self?.onDragEnded() }
        dragMonitor.start()
        _ = panel
        observeEmptyState()
    }

    private func observeEmptyState() {
        withObservationTracking {
            _ = model.items.isEmpty
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeEmptyState()
                self.updateHideSchedule()
            }
        }
    }

    private func onDragStarted() {
        inDrag = true
        cancelHide()
        panel.slideIn()
    }

    private func onDragEnded() {
        inDrag = false
        updateHideSchedule()
    }

    private func handleDrop() {
        cancelHide()
    }

    private func updateHideSchedule() {
        if !inDrag && model.items.isEmpty {
            scheduleHide(after: Self.emptyHideDelay)
        } else {
            cancelHide()
        }
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
