// Runs the unit tests and summarizes the xUnit report they leave behind, so a
// run ends with a count and the names of whatever failed rather than with the
// last few hundred lines of test output.

import Darwin
import Foundation
import ScriptSupport

enum SummaryError: LocalizedError {
    case missingResults(URL)
    case malformedResults(URL)

    var errorDescription: String? {
        switch self {
        case .missingResults(let url):
            "No test results were written to \(url.path)"
        case .malformedResults(let url):
            "No test suite was found in \(url.path)"
        }
    }
}

struct Summary {
    var tests = 0
    var failures = 0
    var errors = 0
    var failed: [String] = []
}

func attribute(_ element: XMLElement, _ name: String) -> String {
    element.attribute(forName: name)?.stringValue ?? ""
}

func summarize(_ results: URL) throws -> Summary {
    guard FileManager.default.isReadableFile(atPath: results.path) else {
        throw SummaryError.missingResults(results)
    }

    let document = try XMLDocument(contentsOf: results)
    let suites = try document.nodes(forXPath: "/testsuites/testsuite").compactMap { $0 as? XMLElement }
    guard !suites.isEmpty else {
        throw SummaryError.malformedResults(results)
    }

    var summary = Summary()
    for suite in suites {
        summary.tests += Int(attribute(suite, "tests")) ?? 0
        summary.failures += Int(attribute(suite, "failures")) ?? 0
        summary.errors += Int(attribute(suite, "errors")) ?? 0
    }
    summary.failed = try document.nodes(forXPath: "//testcase[failure or error]")
        .compactMap { $0 as? XMLElement }
        .map { "\(attribute($0, "classname"))/\(attribute($0, "name"))" }

    return summary
}

do {
    let fileManager = FileManager.default
    let results = projectRoot.appending(path: "build/test-results.xml")
    try? fileManager.removeItem(at: results)
    try fileManager.createDirectory(
        at: results.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    // The suite is XCTest only, and swift-testing writes its own report in its
    // own shape, so leave it switched off and keep one report to read.
    let status = try exitStatus(
        "/usr/bin/swift",
        ["test", "--parallel", "--disable-swift-testing", "--xunit-output", results.path],
        in: projectRoot
    )
    guard fileManager.isReadableFile(atPath: results.path) else {
        // A run that failed before writing a report has already said why. Pass
        // its status on rather than burying that behind a second complaint.
        guard status == EXIT_SUCCESS else { exit(status) }
        throw SummaryError.missingResults(results)
    }

    let summary = try summarize(results)
    for name in summary.failed {
        print("Failed: \(name)")
    }
    print("Tests: \(summary.tests) run, \(summary.failures) failed, \(summary.errors) errors")
    exit(status)
} catch {
    fail(error)
}
