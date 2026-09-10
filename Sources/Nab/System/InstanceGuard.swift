import AppKit

enum InstanceGuard {
    static func otherInstanceProcessIDs() -> [pid_t] {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return [] }
        let processIDs = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .map(\.processIdentifier)
        return otherInstanceProcessIDs(
            in: processIDs,
            excludingProcessID: ProcessInfo.processInfo.processIdentifier
        )
    }

    static func otherInstanceProcessIDs(in processIDs: [pid_t], excludingProcessID processID: pid_t) -> [pid_t] {
        processIDs.filter { $0 != processID }
    }
}
