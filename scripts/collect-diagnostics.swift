// Snapshots everything needed to debug a native crash after the fact: system
// and repository identity, Nab's event journal, its unified log, crash reports,
// and the Debug build's binary identity and symbols. Run before rebuilding,
// since a rebuild destroys the symbols the crash reports point at.
//
// Usage: swift scripts/collect-diagnostics.swift

import CryptoKit
import Darwin
import Foundation

enum DiagnosticsError: LocalizedError {
    case missingBundleIdentifier(URL)
    case commandFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .missingBundleIdentifier(let url):
            "No CFBundleIdentifier in \(url.path)"
        case .commandFailed(let command, let status):
            "\(command) failed with exit status \(status)"
        }
    }
}

func capture(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(filePath: executable)
    process.arguments = arguments
    process.standardOutput = output

    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == EXIT_SUCCESS else {
        let command = ([executable] + arguments).joined(separator: " ")
        throw DiagnosticsError.commandFailed(command, process.terminationStatus)
    }

    return String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Runs a command straight into two files, tolerating failure. The unified log
/// is best effort — it goes quiet once a machine has rotated past the window —
/// and its complaints are worth keeping either way.
func redirect(_ executable: String, _ arguments: [String], output: URL, errorOutput: URL) throws {
    let fileManager = FileManager.default
    fileManager.createFile(atPath: output.path, contents: nil)
    fileManager.createFile(atPath: errorOutput.path, contents: nil)

    let process = Process()
    process.executableURL = URL(filePath: executable)
    process.arguments = arguments
    process.standardOutput = try FileHandle(forWritingTo: output)
    process.standardError = try FileHandle(forWritingTo: errorOutput)

    try process.run()
    process.waitUntilExit()
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
    let projectDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

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
            try capture("/usr/bin/sw_vers", []),
            try capture("/usr/bin/uname", ["-a"]),
            try capture("/usr/bin/arch", []),
        ],
        to: outputDirectory.appending(path: "system.txt")
    )

    let git = "/usr/bin/git"
    try write(
        [
            try capture(git, ["-C", projectDirectory.path, "rev-parse", "HEAD"]),
            try capture(git, ["-C", projectDirectory.path, "status", "--short", "--branch"]),
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
                try capture("/usr/bin/xcrun", ["dwarfdump", "--uuid", executable.path]),
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
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
