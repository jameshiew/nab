import CoreGraphics
import XCTest

@testable import Nab

final class PanelGeometryTests: XCTestCase {
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
