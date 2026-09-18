import Darwin
import Foundation

public enum ScriptError: LocalizedError {
    case commandFailed(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let status):
            "\(command) failed with exit status \(status)"
        }
    }
}

/// The repository these scripts belong to, resolved at compile time so a script
/// behaves the same wherever it is run from.
public let projectRoot = URL(filePath: #filePath)
    .deletingLastPathComponent()  // ScriptSupport
    .deletingLastPathComponent()  // Sources
    .deletingLastPathComponent()  // scripts
    .deletingLastPathComponent()

/// Reports a thrown error the way a command line tool should, rather than
/// trapping and burying it in a stack trace.
public func fail(_ error: any Error) -> Never {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}

/// Runs a command and fails if it does. Output is inherited unless it is
/// captured, so a build's progress still reaches the terminal.
@discardableResult
public func run(
    _ executable: String,
    _ arguments: [String],
    in directory: URL? = nil,
    capturingOutput: Bool = false
) throws -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(filePath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = directory
    if capturingOutput {
        process.standardOutput = output
    }

    try process.run()
    let data = capturingOutput ? output.fileHandleForReading.readDataToEndOfFile() : Data()
    process.waitUntilExit()

    guard process.terminationStatus == EXIT_SUCCESS else {
        let command = ([executable] + arguments).joined(separator: " ")
        throw ScriptError.commandFailed(command, process.terminationStatus)
    }

    return String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Runs a command straight into two files, tolerating failure. Some tools are
/// worth attempting on a machine that will refuse them, and what they said on
/// the way out is worth keeping either way.
public func redirect(
    _ executable: String,
    _ arguments: [String],
    output: URL,
    errorOutput: URL
) throws {
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
