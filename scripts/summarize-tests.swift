// Summarizes the xUnit report left behind by `swift test --xunit-output`, so a
// run ends with a count and the names of whatever failed.
//
// Usage: swift scripts/summarize-tests.swift <results-file>

import Darwin
import Foundation

enum SummaryError: LocalizedError {
    case usage
    case missingResults(URL)
    case malformedResults(URL)

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: summarize-tests.swift <results-file>"
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
    let arguments = CommandLine.arguments.dropFirst()
    guard let path = arguments.first, arguments.count == 1 else {
        throw SummaryError.usage
    }

    let summary = try summarize(URL(filePath: path))
    for name in summary.failed {
        print("Failed: \(name)")
    }
    print("Tests: \(summary.tests) run, \(summary.failures) failed, \(summary.errors) errors")
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
