import Foundation
import XCTest

@testable import Nab

@MainActor
final class DiagnosticsRecorderTests: XCTestCase {
    func testRecordsUnexpectedPreviousSessionAndCleanTermination() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try "previous-session".write(
            to: directoryURL.appendingPathComponent("active-session"),
            atomically: true,
            encoding: .utf8
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let sessionID = UUID()
        let recorder = DiagnosticsRecorder(
            directoryURL: directoryURL,
            sessionID: sessionID,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        recorder.start()
        recorder.record("test_event", details: ["count": "2"])
        recorder.finish()

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directoryURL.appendingPathComponent("active-session").path
            )
        )
        let eventLogURL = directoryURL.appendingPathComponent(
            "session-\(sessionID.uuidString.lowercased()).jsonl"
        )
        let events = try String(contentsOf: eventLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map {
                try XCTUnwrap(
                    JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
                )
            }

        XCTAssertEqual(
            events.compactMap { $0["name"] as? String },
            [
                "previous_session_ended_unexpectedly",
                "application_started",
                "test_event",
                "application_will_terminate",
            ]
        )
        XCTAssertEqual(
            (events[0]["details"] as? [String: String])?["previous_session_id"],
            "previous-session"
        )
        XCTAssertEqual((events[2]["details"] as? [String: String])?["count"], "2")
    }
}
