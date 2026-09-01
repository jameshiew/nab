import AppKit

enum DragOperationPolicy {
    nonisolated static func sourceMask(containsMaterializedFiles: Bool) -> NSDragOperation {
        containsMaterializedFiles ? .copy : [.move, .copy]
    }

    nonisolated static func shouldRemoveItems(after operation: NSDragOperation) -> Bool {
        operation.contains(.move)
    }
}
