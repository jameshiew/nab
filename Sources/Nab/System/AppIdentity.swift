import Foundation

nonisolated enum AppIdentity {
    static let defaultBundleIdentifier = "net.hiew.Nab"
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? defaultBundleIdentifier

    static func namespaced(_ name: String) -> String {
        "\(bundleIdentifier).\(name)"
    }
}
