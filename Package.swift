// swift-tools-version: 6.2

import PackageDescription

let approachableConcurrency: [SwiftSetting] = [
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "Nab",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Nab", targets: ["Nab"])
    ],
    targets: [
        .executableTarget(
            name: "Nab",
            path: "Nab",
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ] + approachableConcurrency
        ),
        .testTarget(
            name: "NabTests",
            dependencies: ["Nab"],
            path: "NabTests",
            swiftSettings: approachableConcurrency
        ),
    ],
    swiftLanguageModes: [.v6]
)
