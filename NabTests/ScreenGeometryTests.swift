import CoreGraphics
import XCTest

@testable import Nab

final class ScreenGeometryTests: XCTestCase {
    func testBestMatchingScreenSupportsNegativeDisplayCoordinates() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            CGRect(x: -1_280, y: 0, width: 1_280, height: 1_024),
        ]
        let frame = CGRect(x: -1_100, y: 200, width: 400, height: 400)

        XCTAssertEqual(ScreenGeometry.bestMatchingIndex(for: frame, in: screens), 1)
    }

    func testBestMatchingScreenSupportsDisplayAbovePrimary() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            CGRect(x: 200, y: 1_080, width: 1_440, height: 900),
        ]
        let frame = CGRect(x: 800, y: 1_300, width: 400, height: 400)

        XCTAssertEqual(ScreenGeometry.bestMatchingIndex(for: frame, in: screens), 1)
    }

    func testBestMatchingScreenReturnsNilWithoutScreens() {
        XCTAssertNil(ScreenGeometry.bestMatchingIndex(for: .zero, in: []))
    }

    func testClampingUsesSelectedScreensCoordinateSpace() {
        let screen = CGRect(x: -1_280, y: 0, width: 1_280, height: 1_024)
        let frame = CGRect(x: -1_500, y: -200, width: 400, height: 400)

        XCTAssertEqual(
            ScreenGeometry.clampedFrame(frame, to: screen),
            CGRect(x: -1_280, y: 0, width: 400, height: 400)
        )
    }
}
