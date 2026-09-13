import AppKit
import os

enum Log {
    static let shelf = Logger(subsystem: AppIdentity.bundleIdentifier, category: "Shelf")
}

enum ShelfFeedback {
    static func rejectedDrop() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        NSCursor.disappearingItem.push()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSCursor.pop()
        }
    }
}
