import AppKit
import Foundation
import os

@MainActor
final class DiagnosticsRecorder {
    static let shared = DiagnosticsRecorder()

    private struct Event: Encodable {
        let schemaVersion = 1
        let timestamp: String
        let sessionID: String
        let name: String
        let details: [String: String]
    }

    private let directoryURL: URL
    private let eventLogURL: URL
    private let activeSessionURL: URL
    private let sessionID: UUID
    private let now: () -> Date
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "dev.nab.Nab", category: "Diagnostics")
    private var started = false

    init(
        directoryURL: URL = DiagnosticsRecorder.defaultDirectoryURL(),
        sessionID: UUID = UUID(),
        now: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.sessionID = sessionID
        self.now = now
        self.fileManager = fileManager
        eventLogURL = directoryURL.appendingPathComponent(
            "session-\(sessionID.uuidString.lowercased()).jsonl"
        )
        activeSessionURL = directoryURL.appendingPathComponent("active-session")
    }

    func start() {
        guard !started else { return }
        started = true

        let previousSessionID = try? String(contentsOf: activeSessionURL, encoding: .utf8)
        if let previousSessionID, !previousSessionID.isEmpty {
            record(
                "previous_session_ended_unexpectedly",
                details: ["previous_session_id": previousSessionID]
            )
        }

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try sessionID.uuidString.lowercased().write(
                to: activeSessionURL,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            logger.error(
                "Failed to create diagnostics session marker: \(error.localizedDescription, privacy: .private)"
            )
        }

        record(
            "application_started",
            details: [
                "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                    ?? "unknown",
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "pid": String(ProcessInfo.processInfo.processIdentifier),
                "version": Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString"
                ) as? String ?? "unknown",
            ]
        )
    }

    func finish() {
        guard started else { return }
        record("application_will_terminate")

        do {
            let activeSessionID = try String(contentsOf: activeSessionURL, encoding: .utf8)
            if activeSessionID == sessionID.uuidString.lowercased() {
                try fileManager.removeItem(at: activeSessionURL)
            }
        } catch CocoaError.fileReadNoSuchFile {
        } catch {
            logger.error(
                "Failed to clear diagnostics session marker: \(error.localizedDescription, privacy: .private)"
            )
        }
        started = false
    }

    func record(_ name: String, details: [String: String] = [:]) {
        let event = Event(
            timestamp: now().ISO8601Format(.iso8601(timeZone: .gmt, includingFractionalSeconds: true)),
            sessionID: sessionID.uuidString.lowercased(),
            name: name,
            details: details
        )

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            var data = try encoder.encode(event)
            data.append(0x0A)
            if !fileManager.fileExists(atPath: eventLogURL.path) {
                fileManager.createFile(atPath: eventLogURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: eventLogURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            logger.log("\(name, privacy: .public) \(details.description, privacy: .public)")
        } catch {
            logger.error(
                "Failed to append diagnostic event \(name, privacy: .public): \(error.localizedDescription, privacy: .private)"
            )
        }
    }

    func revealInFinder() {
        record("diagnostics_revealed")
        NSWorkspace.shared.activateFileViewerSelecting([eventLogURL])
    }

    private static func defaultDirectoryURL() -> URL {
        let libraryURL =
            FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return
            libraryURL
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Nab", isDirectory: true)
    }
}
