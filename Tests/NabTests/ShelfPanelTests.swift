import AppKit
import SwiftUI
import XCTest

@testable import Nab

@MainActor
final class ShelfPanelTests: XCTestCase {
    func testDragUsesPointerDisplayAndResizesShelfToFit() async throws {
        let displays = makeDisplays()
        let panel = makePanel(displays: { displays })
        defer { panel.close() }
        panel.updateHeight(forItemCount: 10)

        panel.slideIn(at: CGPoint(x: -500, y: 500))
        try await Task.sleep(for: .milliseconds(350))

        XCTAssertEqual(panel.visibleFrame, CGRect(x: -232, y: 140, width: 220, height: 640))
        XCTAssertEqual(panel.frame, panel.visibleFrame)
        XCTAssertFalse(panel.isKeyWindow)

        panel.slideIn(at: CGPoint(x: 500, y: 500))
        try await Task.sleep(for: .milliseconds(350))

        XCTAssertEqual(panel.visibleFrame, CGRect(x: 1_688, y: 40, width: 220, height: 1_000))
        XCTAssertEqual(panel.frame, panel.visibleFrame)
    }

    func testShelfKeepsPresentationDisplayWhenUpdatingContent() {
        let source = DisplaySource(makeDisplays())
        let panel = makePanel(displays: { source.displays })
        defer { panel.close() }
        panel.slideIn(at: CGPoint(x: -500, y: 500))
        source.displays.reverse()

        panel.updateHeight(forItemCount: 10)

        XCTAssertEqual(panel.visibleFrame, CGRect(x: -232, y: 140, width: 220, height: 640))
    }

    func testSavedPositionIsUsedOnlyOnTheSelectedDisplay() {
        let displays = makeDisplays()
        let panel = makePanel(
            displays: { displays },
            customTopLeft: CGPoint(x: 300, y: 900)
        )
        defer { panel.close() }

        panel.slideIn(at: CGPoint(x: -500, y: 500))

        XCTAssertEqual(panel.visibleFrame, CGRect(x: -232, y: 280, width: 220, height: 360))

        panel.slideIn(at: CGPoint(x: 500, y: 500))

        XCTAssertEqual(panel.visibleFrame, CGRect(x: 300, y: 540, width: 220, height: 360))
    }

    func testDisplayChangeRepositionsAndRestoresShownShelfWithoutTakingFocus() async throws {
        let source = DisplaySource(Array(makeDisplays().prefix(1)))
        let panel = makePanel(displays: { source.displays })
        defer { panel.close() }
        panel.updateHeight(forItemCount: 10)
        panel.slideIn(at: CGPoint(x: 500, y: 500))
        panel.orderOut(nil)
        source.displays = [
            ShelfPanel.Display(
                id: source.displays[0].id,
                frame: CGRect(x: -1_280, y: 100, width: 1_280, height: 720),
                visibleFrame: CGRect(x: -1_280, y: 100, width: 1_280, height: 720)
            )
        ]

        postDisplayChange()
        try await Task.sleep(for: .milliseconds(350))

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.frame, CGRect(x: -232, y: 140, width: 220, height: 640))
        XCTAssertFalse(panel.isKeyWindow)
    }

    func testDisconnectingPresentationDisplayMovesShelfToRemainingDisplay() async throws {
        let source = DisplaySource(makeDisplays())
        let panel = makePanel(displays: { source.displays })
        defer { panel.close() }
        panel.updateHeight(forItemCount: 10)
        panel.slideIn(at: CGPoint(x: -500, y: 500))
        try await Task.sleep(for: .milliseconds(50))
        source.displays.removeLast()

        postDisplayChange()
        try await Task.sleep(for: .milliseconds(350))

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.frame, CGRect(x: 1_688, y: 40, width: 220, height: 1_000))
        XCTAssertFalse(panel.isKeyWindow)
    }

    func testDisplayChangeLeavesHiddenShelfHidden() {
        let displays = makeDisplays()
        let panel = makePanel(displays: { displays })
        defer { panel.close() }

        postDisplayChange()

        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(panel.frame, panel.edgeFrame)
    }

    func testDisplayChangeDoesNotRestoreShelfThatIsSlidingOut() async throws {
        let displays = makeDisplays()
        let panel = makePanel(displays: { displays })
        defer { panel.close() }
        panel.slideIn(at: CGPoint(x: 500, y: 500))
        panel.slideOut()

        postDisplayChange()
        try await Task.sleep(for: .milliseconds(350))

        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(panel.frame, panel.edgeFrame)
    }

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

    private func makePanel(
        displays: (@MainActor () -> [ShelfPanel.Display])? = nil,
        customTopLeft: CGPoint? = nil
    ) -> ShelfPanel {
        _ = NSApplication.shared
        if let displays {
            return ShelfPanel(rootView: EmptyView(), displays: displays, customTopLeft: customTopLeft)
        }
        return ShelfPanel(rootView: EmptyView(), customTopLeft: customTopLeft)
    }

    private func makeDisplays() -> [ShelfPanel.Display] {
        [
            ShelfPanel.Display(
                id: 1,
                frame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
                visibleFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
            ),
            ShelfPanel.Display(
                id: 2,
                frame: CGRect(x: -1_280, y: 100, width: 1_280, height: 720),
                visibleFrame: CGRect(x: -1_280, y: 100, width: 1_280, height: 720)
            ),
        ]
    }

    private func postDisplayChange() {
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: NSApplication.shared
        )
    }

    private func postSpaceChange() {
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )
    }

    @MainActor
    private final class DisplaySource {
        var displays: [ShelfPanel.Display]

        init(_ displays: [ShelfPanel.Display]) {
            self.displays = displays
        }
    }
}
