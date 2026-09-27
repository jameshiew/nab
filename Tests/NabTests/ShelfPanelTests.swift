import AppKit
import SwiftUI
import XCTest

@testable import Nab

@MainActor
final class ShelfPanelTests: XCTestCase {
    func testSpaceChangeRestoresShownShelfWithoutTakingFocus() {
        let panel = makePanel()
        defer { panel.close() }
        panel.slideIn()
        let frame = panel.frame
        panel.orderOut(nil)
        XCTAssertFalse(panel.isVisible)

        postSpaceChange()

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.frame, frame)
        XCTAssertFalse(panel.isKeyWindow)
    }

    func testSpaceChangeLeavesHiddenShelfHidden() {
        let panel = makePanel()
        defer { panel.close() }

        postSpaceChange()

        XCTAssertFalse(panel.isVisible)
    }

    func testSpaceChangeDoesNotRestoreShelfThatIsSlidingOut() {
        let panel = makePanel()
        defer { panel.close() }
        panel.slideIn()
        panel.slideOut()
        panel.orderOut(nil)

        postSpaceChange()

        XCTAssertFalse(panel.isVisible)
    }

    private func makePanel() -> ShelfPanel {
        _ = NSApplication.shared
        return ShelfPanel(rootView: EmptyView())
    }

    private func postSpaceChange() {
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )
    }
}
