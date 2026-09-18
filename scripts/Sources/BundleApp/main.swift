import Foundation
import ScriptSupport

enum BundleError: LocalizedError {
    case invalidConfiguration(String)
    case missingExecutable(URL)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let value):
            "Unknown build configuration: \(value)"
        case .missingExecutable(let url):
            "SwiftPM did not produce an executable at \(url.path)"
        }
    }
}

enum BuildConfiguration: String {
    case debug
    case release
}

func bundleApplication(configuration: BuildConfiguration) throws -> URL {
    let fileManager = FileManager.default
    let swift = "/usr/bin/swift"

    try run(
        swift,
        ["build", "--configuration", configuration.rawValue, "--product", "Nab"],
        in: projectRoot
    )
    let binaryDirectory = try run(
        swift,
        ["build", "--configuration", configuration.rawValue, "--show-bin-path"],
        in: projectRoot,
        capturingOutput: true
    )
    let executable = URL(filePath: binaryDirectory).appending(path: "Nab")
    guard fileManager.isExecutableFile(atPath: executable.path) else {
        throw BundleError.missingExecutable(executable)
    }

    let outputDirectory =
        projectRoot
        .appending(path: "build")
        .appending(path: configuration.rawValue)
    let application = outputDirectory.appending(path: "Nab.app")
    let stagingDirectory = outputDirectory.appending(path: ".Nab-\(UUID().uuidString)")
    let stagingApplication = stagingDirectory.appending(path: "Nab.app")
    let stagingSymbols = stagingDirectory.appending(path: "Nab.app.dSYM")
    let contents = stagingApplication.appending(path: "Contents")
    let macOS = contents.appending(path: "MacOS")
    let resources = contents.appending(path: "Resources")

    try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: stagingDirectory) }
    try fileManager.createDirectory(at: macOS, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)

    let bundledExecutable = macOS.appending(path: "Nab")
    try fileManager.copyItem(at: executable, to: bundledExecutable)
    try fileManager.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: bundledExecutable.path
    )

    let sourceResources = projectRoot.appending(path: "Sources/Nab/Resources")
    try fileManager.copyItem(
        at: sourceResources.appending(path: "Info.plist"),
        to: contents.appending(path: "Info.plist")
    )
    try Data("APPL????".utf8).write(to: contents.appending(path: "PkgInfo"))

    try run(
        "/usr/bin/iconutil",
        [
            "--convert", "icns",
            "--output", resources.appending(path: "AppIcon.icns").path,
            sourceResources.appending(path: "AppIcon.iconset").path,
        ],
        in: projectRoot
    )
    try run(
        "/usr/bin/plutil",
        ["-lint", contents.appending(path: "Info.plist").path],
        in: projectRoot
    )
    try run(
        "/usr/bin/xcrun",
        ["dsymutil", executable.path, "-o", stagingSymbols.path],
        in: projectRoot
    )
    var signingArguments = [
        "--force", "--sign", "-", "--options", "runtime", "--timestamp=none",
    ]
    if configuration == .debug {
        signingArguments += ["--entitlements", sourceResources.appending(path: "NabDebug.entitlements").path]
    }
    signingArguments.append(stagingApplication.path)
    try run(
        "/usr/bin/codesign",
        signingArguments,
        in: projectRoot
    )
    try run(
        "/usr/bin/codesign",
        ["--verify", "--deep", "--strict", "--verbose=2", stagingApplication.path],
        in: projectRoot
    )

    if fileManager.fileExists(atPath: application.path) {
        try fileManager.removeItem(at: application)
    }
    try fileManager.moveItem(at: stagingApplication, to: application)
    let symbols = outputDirectory.appending(path: "Nab.app.dSYM")
    if fileManager.fileExists(atPath: symbols.path) {
        try fileManager.removeItem(at: symbols)
    }
    try fileManager.moveItem(at: stagingSymbols, to: symbols)

    return application
}

do {
    let value = CommandLine.arguments.dropFirst().first ?? BuildConfiguration.debug.rawValue
    guard CommandLine.arguments.count <= 2, let configuration = BuildConfiguration(rawValue: value)
    else {
        throw BundleError.invalidConfiguration(value)
    }

    let application = try bundleApplication(configuration: configuration)
    print("Built \(application.path)")
} catch {
    fail(error)
}
