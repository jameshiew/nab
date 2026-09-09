import ServiceManagement
import XCTest

@testable import Nab

@MainActor
final class LoginItemStateTests: XCTestCase {
    func testMapsServiceStatuses() {
        XCTAssertEqual(LoginItemState(.notRegistered), .disabled)
        XCTAssertEqual(LoginItemState(.enabled), .enabled)
        XCTAssertEqual(LoginItemState(.requiresApproval), .requiresApproval)
        XCTAssertEqual(LoginItemState(.notFound), .unavailable)
    }

    func testEnabledAndApprovalRequiredStatesAppearOn() {
        XCTAssertFalse(LoginItemState.disabled.isOn)
        XCTAssertTrue(LoginItemState.enabled.isOn)
        XCTAssertTrue(LoginItemState.requiresApproval.isOn)
        XCTAssertFalse(LoginItemState.unavailable.isOn)
    }

    func testOnlyUnavailableStateDisablesControl() {
        XCTAssertTrue(LoginItemState.disabled.isAvailable)
        XCTAssertTrue(LoginItemState.enabled.isAvailable)
        XCTAssertTrue(LoginItemState.requiresApproval.isAvailable)
        XCTAssertFalse(LoginItemState.unavailable.isAvailable)
    }
}
