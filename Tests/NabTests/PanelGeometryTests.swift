import CoreGraphics
import XCTest

@testable import Nab

final class PanelGeometryTests: XCTestCase {
    func testMovingExpandedShelfToShorterDisplayKeepsHeaderVisible() {
        let screen = CGRect(x: -1_280, y: 100, width: 1_280, height: 720)
        let height = PanelGeometry.height(forItemCount: 10, screenHeight: 1_080)
        let draggedFrame = CGRect(x: -232, y: -280, width: 220, height: height)

        let resizedFrame = PanelGeometry.resizedVisibleFrame(
            for: draggedFrame,
            itemCount: 10,
            in: screen
        )

        XCTAssertEqual(resizedFrame, CGRect(x: -232, y: 100, width: 220, height: 640))
        XCTAssertTrue(screen.contains(resizedFrame))
    }

    func testMovingShelfToTallerDisplayRestoresContentHeight() {
        let screen = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let draggedFrame = CGRect(x: 300, y: 400, width: 220, height: 640)

        let resizedFrame = PanelGeometry.resizedVisibleFrame(
            for: draggedFrame,
            itemCount: 10,
            in: screen
        )

        XCTAssertEqual(resizedFrame, CGRect(x: 300, y: 40, width: 220, height: 1_000))
        XCTAssertEqual(resizedFrame.maxY, draggedFrame.maxY)
    }

    func testMovingEmptyShelfToDisplayShorterThanBaseHeightFitsDisplay() {
        let screen = CGRect(x: 0, y: 100, width: 1_280, height: 300)
        let draggedFrame = CGRect(x: 300, y: 140, width: 220, height: 360)

        XCTAssertEqual(
            PanelGeometry.resizedVisibleFrame(for: draggedFrame, itemCount: 0, in: screen),
            CGRect(x: 300, y: 100, width: 220, height: 300)
        )
    }

    func testMissingScreensLeavesFrameUnchanged() {
        let visibleFrame = CGRect(x: 12, y: 360, width: 220, height: 360)

        XCTAssertEqual(
            PanelGeometry.frameAtNearestHorizontalEdge(for: visibleFrame, in: []),
            visibleFrame
        )
    }

    func testSideBySideDisplaysKeepEdgeFrameOnCurrentDisplay() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            CGRect(x: 1_920, y: 0, width: 1_920, height: 1_080),
        ]
        let visibleFrame = CGRect(x: 1_688, y: 360, width: 220, height: 360)

        let edgeFrame = PanelGeometry.frameAtNearestHorizontalEdge(
            for: visibleFrame,
            in: screens
        )

        XCTAssertEqual(edgeFrame, CGRect(x: 1_700, y: 360, width: 220, height: 360))
        XCTAssertEqual(ScreenGeometry.intersectionArea(edgeFrame, screens[1]), 0)
    }

    func testShelfNearLeftEdgeDoesNotCrossDesktopToHide() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            CGRect(x: 1_920, y: 0, width: 1_920, height: 1_080),
        ]
        let visibleFrame = CGRect(x: 12, y: 360, width: 220, height: 360)

        let edgeFrame = PanelGeometry.frameAtNearestHorizontalEdge(
            for: visibleFrame,
            in: screens
        )

        XCTAssertEqual(edgeFrame, CGRect(x: 0, y: 360, width: 220, height: 360))
    }

    func testVerticallyStackedDisplaysUseMatchingDisplayEdge() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            CGRect(x: 200, y: 1_080, width: 1_440, height: 900),
        ]
        let visibleFrame = CGRect(x: 212, y: 1_300, width: 220, height: 360)

        let edgeFrame = PanelGeometry.frameAtNearestHorizontalEdge(
            for: visibleFrame,
            in: screens
        )

        XCTAssertEqual(edgeFrame, CGRect(x: 200, y: 1_300, width: 220, height: 360))
    }

    func testNegativeCoordinateDisplayUsesItsNearestEdge() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            CGRect(x: -1_280, y: 0, width: 1_280, height: 1_024),
        ]
        let visibleFrame = CGRect(x: -232, y: 332, width: 220, height: 360)

        let edgeFrame = PanelGeometry.frameAtNearestHorizontalEdge(
            for: visibleFrame,
            in: screens
        )

        XCTAssertEqual(edgeFrame, CGRect(x: -220, y: 332, width: 220, height: 360))
        XCTAssertEqual(ScreenGeometry.intersectionArea(edgeFrame, screens[0]), 0)
    }
}
