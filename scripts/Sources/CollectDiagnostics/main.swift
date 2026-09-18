// Snapshots everything needed to debug a native crash after the fact: system
// and repository identity, Nab's event journal, its unified log, crash reports,
// and the Debug build's binary identity and symbols. Run before rebuilding,
// since a rebuild destroys the symbols the crash reports point at.

import CryptoKit
import Foundation
import ScriptSupport

enum DiagnosticsError: LocalizedError {
    case missingBundleIdentifier(URL)

    var errorDescription: String? {
        switch self {
        case .missingBundleIdentifier(let url):
            "No CFBundleIdentifier in \(url.path)"
        }
    }
}

func write(_ sections: [String], to url: URL) throws {
    try sections.map { $0 + "\n" }
        .joined()
        .write(to: url, atomically: true, encoding: .utf8)
}

/// Files in a directory touched within the last week, which is as far back as a
/// crash still worth debugging is likely to be.
func recentFiles(in directory: URL) -> [URL] {
    let cutoff = Date.now.addingTimeInterval(-7 * 24 * 60 * 60)
    let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
    let contents =
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys
        )) ?? []

    return contents.filter { url in
        guard let values = try? url.resourceValues(forKeys: Set(keys)),
            values.isRegularFile == true,
            let modified = values.contentModificationDate
        else {
            return false
        }
        return modified >= cutoff
    }
}

func collectDiagnostics() throws -> URL {
    let fileManager = FileManager.default
    let projectDirectory = projectRoot

    let infoPlist = projectDirectory.appending(path: "Sources/Nab/Resources/Info.plist")
    let information = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoPlist), format: nil)
    guard let bundleIdentifier = (information as? [String: Any])?["CFBundleIdentifier"] as? String else {
        throw DiagnosticsError.missingBundleIdentifier(infoPlist)
    }

    let timestamp = Date.ISO8601FormatStyle(
        dateSeparator: .omitted,
        timeSeparator: .omitted,
        timeZone: .gmt
    ).format(.now)
    let outputDirectory = projectDirectory.appending(path: "build/diagnostics/\(timestamp)")
    let events = outputDirectory.appending(path: "nab-events")
    let crashReports = outputDirectory.appending(path: "crash-reports")
    try fileManager.createDirectory(at: events, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: crashReports, withIntermediateDirectories: true)

    try write(
        [
            try run("/usr/bin/sw_vers", [], capturingOutput: true),
            try run("/usr/bin/uname", ["-a"], capturingOutput: true),
            try run("/usr/bin/arch", [], capturingOutput: true),
        ],
        to: outputDirectory.appending(path: "system.txt")
    )

    let git = "/usr/bin/git"
    try write(
        [
            try run(git, ["-C", projectDirectory.path, "rev-parse", "HEAD"], capturingOutput: true),
            try run(git, ["-C", projectDirectory.path, "status", "--short", "--branch"], capturingOutput: true),
        ],
        to: outputDirectory.appending(path: "repository.txt")
    )

    let library = fileManager.homeDirectoryForCurrentUser.appending(path: "Library")
    for log in recentFiles(in: library.appending(path: "Logs/Nab")) {
        try fileManager.copyItem(at: log, to: events.appending(path: log.lastPathComponent))
    }

    try redirect(
        "/usr/bin/log",
        [
            "show",
            "--style", "json",
            "--last", "24h",
            "--info",
            "--debug",
            "--predicate", "subsystem == \"\(bundleIdentifier)\"",
        ],
        output: outputDirectory.appending(path: "unified-log.jsonl"),
        errorOutput: outputDirectory.appending(path: "unified-log-error.txt")
    )

    let reports = recentFiles(in: library.appending(path: "Logs/DiagnosticReports"))
        .filter { $0.lastPathComponent.hasPrefix("Nab") && $0.pathExtension == "ips" }
    for report in reports {
        try fileManager.copyItem(at: report, to: crashReports.appending(path: report.lastPathComponent))
    }

    let debugDirectory = projectDirectory.appending(path: "build/debug")
    let executable = debugDirectory.appending(path: "Nab.app/Contents/MacOS/Nab")
    if fileManager.isExecutableFile(atPath: executable.path) {
        let digest = SHA256.hash(data: try Data(contentsOf: executable, options: .mappedIfSafe))
        let checksum = digest.map { String(format: "%02x", $0) }.joined()
        try write(
            [
                try run("/usr/bin/xcrun", ["dwarfdump", "--uuid", executable.path], capturingOutput: true),
                "\(checksum)  \(executable.path)",
            ],
            to: outputDirectory.appending(path: "debug-binary.txt")
        )
    }

    let debugSymbols = debugDirectory.appending(path: "Nab.app.dSYM")
    if fileManager.fileExists(atPath: debugSymbols.path) {
        let symbols = outputDirectory.appending(path: "symbols")
        try fileManager.createDirectory(at: symbols, withIntermediateDirectories: true)
        try fileManager.copyItem(at: debugSymbols, to: symbols.appending(path: "Nab.app.dSYM"))
    }

    return outputDirectory
}

do {
    print(try collectDiagnostics().path)
} catch {
    fail(error)
}
