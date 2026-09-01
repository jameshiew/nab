import AppKit

enum DragOperationPolicy {
    nonisolated static func shouldRemoveItems(after operation: NSDragOperation) -> Bool {
        operation.contains(.move)
    }
}
