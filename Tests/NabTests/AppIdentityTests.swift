import Foundation
import XCTest

@testable import Nab

final class AppIdentityTests: XCTestCase {
    func testUnbundledIdentifierMatchesAppMetadata() throws {
        let packageRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: packageRoot.appending(path: "Sources/Nab/Resources/Info.plist"))
        let metadata = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(metadata["CFBundleIdentifier"] as? String, AppIdentity.defaultBundleIdentifier)
    }
}
