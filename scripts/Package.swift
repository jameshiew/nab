// swift-tools-version: 6.2

import PackageDescription

/// The project's own tooling, kept in its own package so the scripts stay
/// compiled and share code without adding products to the Nab package or
/// nesting a SwiftPM build inside one that already holds the same lock.
let package = Package(
    name: "NabScripts",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "bundle-app", targets: ["BundleApp"]),
        .executable(name: "collect-diagnostics", targets: ["CollectDiagnostics"]),
        .executable(name: "generate-app-icon", targets: ["GenerateAppIcon"]),
        .executable(name: "run-tests", targets: ["RunTests"]),
    ],
    targets: [
        .target(name: "ScriptSupport"),
        .executableTarget(name: "BundleApp", dependencies: ["ScriptSupport"]),
        .executableTarget(name: "CollectDiagnostics", dependencies: ["ScriptSupport"]),
        .executableTarget(name: "GenerateAppIcon", dependencies: ["ScriptSupport"]),
        .executableTarget(name: "RunTests", dependencies: ["ScriptSupport"]),
    ],
    swiftLanguageModes: [.v6]
)
