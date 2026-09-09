import AppKit
import Observation
import SwiftUI

@MainActor
final class ShelfController {
    private let materializedFileStore: MaterializedFileStore
    private let model: ShelfModel

    init(materializedFileStore: MaterializedFileStore = .shared) {
        self.materializedFileStore = materializedFileStore
        model = ShelfModel(materializedFileStore: materializedFileStore)
    }

    private lazy var exportCoordinator = FileExportCoordinator(
        materializedFileStore: materializedFileStore,
        onItemsExported: { [weak self] itemIDs in
            self?.model.remove(ids: itemIDs)
        }
    )
    private lazy var panel: ShelfPanel = {
        let view = ShelfView(
            model: model,
            exportCoordinator: exportCoordinator,
            materializedFileStore: materializedFileStore,
            onDropReceived: { [weak self] in self?.handleDrop() },
            onDropPartiallyFailed: { [weak self] in self?.presentPartialDropFailure($0) },
            onPromiseDropStarted: { [weak self] in self?.promiseDropStarted() },
            onPromiseDropFinished: { [weak self] in self?.promiseDropFinished() },
            onItemDragEnded: { [weak self] in self?.dragMonitor.endDrag() },
            onHeaderDragEnded: { [weak self] in self?.panel.userDidFinishDragging() }
        )
        return ShelfPanel(rootView: view)
    }()
    private let dragMonitor = DragMonitor()
    private var hideTask: Task<Void, Never>?
    private var inDrag = false
    private var pendingPromiseDropCount = 0
    private var cursorInsideShelf = false
    private var pendingDropFailureMessages: [String] = []
    private var isPresentingDropFailure = false

    private static let emptyHideDelay: Duration = .milliseconds(400)

    func start() {
        materializedFileStore.trashAbandonedMaterializations()
        dragMonitor.dragStarted = { [weak self] in self?.onDragStarted() }
        dragMonitor.dragEnded = { [weak self] in self?.onDragEnded() }
        dragMonitor.dragMoved = { [weak self] point in self?.onDragMoved(at: point) }
        dragMonitor.start()
        _ = panel
        observeItems()
    }

    func stop() {
        cancelHide()
        dragMonitor.stop()
        model.clear()
        materializedFileStore.waitForPendingOperations()
    }

    private func observeItems() {
        withObservationTracking {
            _ = model.items
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeItems()
                self.panel.updateHeight(forItemCount: self.model.items.count)
                self.updateHideSchedule()
            }
        }
    }

    private func onDragStarted() {
        inDrag = true
        cursorInsideShelf = panel.visibleFrame.contains(NSEvent.mouseLocation)
        cancelHide()
        panel.slideIn()
    }

    private func onDragEnded() {
        inDrag = false
        updateHideSchedule()
    }

    private func onDragMoved(at point: NSPoint) {
        let inside = panel.visibleFrame.contains(point)
        guard inside != cursorInsideShelf else { return }
        cursorInsideShelf = inside
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func handleDrop() {
        cancelHide()
    }

    private func promiseDropStarted() {
        pendingPromiseDropCount += 1
        cancelHide()
    }

    private func promiseDropFinished() {
        pendingPromiseDropCount = max(0, pendingPromiseDropCount - 1)
        updateHideSchedule()
    }

    private func presentPartialDropFailure(_ result: InboundDropResult) {
        guard let message = result.partialFailureMessage else { return }
        pendingDropFailureMessages.append(message)
        presentNextDropFailure()
    }

    private func presentNextDropFailure() {
        guard !isPresentingDropFailure, !pendingDropFailureMessages.isEmpty else { return }
        let message = pendingDropFailureMessages.removeFirst()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Some Files Couldn’t Be Parked"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        isPresentingDropFailure = true
        NSApp.activate()
        alert.beginSheetModal(for: panel) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPresentingDropFailure = false
                self.presentNextDropFailure()
            }
        }
    }

    private func updateHideSchedule() {
        if !inDrag && pendingPromiseDropCount == 0 && model.items.isEmpty {
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
