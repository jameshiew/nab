import XCTest

@testable import Nab

@MainActor
final class InstanceGuardTests: XCTestCase {
    func testReportsEveryProcessExceptTheCurrentOne() {
        XCTAssertEqual(
            InstanceGuard.otherInstanceProcessIDs(in: [10, 20, 30], excludingProcessID: 20),
            [10, 30]
        )
    }

    func testReportsNothingWhenOnlyTheCurrentProcessIsRunning() {
        XCTAssertTrue(InstanceGuard.otherInstanceProcessIDs(in: [20], excludingProcessID: 20).isEmpty)
        XCTAssertTrue(InstanceGuard.otherInstanceProcessIDs(in: [], excludingProcessID: 20).isEmpty)
    }
}
