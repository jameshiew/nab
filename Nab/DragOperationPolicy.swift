import AppKit

enum DragOperationPolicy {
    nonisolated static func sourceMask(
        for context: NSDraggingContext,
        containsMaterializedFiles: Bool
    ) -> NSDragOperation {
        if containsMaterializedFiles {
            return .copy
        }

        switch context {
        case .withinApplication:
            return .move
        case .outsideApplication:
            return .copy
        @unknown default:
            return .copy
        }
    }

    nonisolated static func shouldRemoveItems(after operation: NSDragOperation) -> Bool {
        operation.contains(.move)
    }
}
