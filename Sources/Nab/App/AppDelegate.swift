import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = ShelfController()
    private let diagnostics = DiagnosticsRecorder.shared
    private var hasStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let otherInstances = InstanceGuard.otherInstanceProcessIDs()
        guard otherInstances.isEmpty else {
            diagnostics.record(
                "launch_refused_other_instance_running",
                details: [
                    "other_process_ids": otherInstances.map(String.init).joined(separator: ",")
                ]
            )
            NSApp.terminate(nil)
            return
        }

        hasStarted = true
        diagnostics.start()
        NSApp.setActivationPolicy(.accessory)
        controller.start()
        diagnostics.record("application_ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard hasStarted else { return }
        diagnostics.record("application_termination_started")
        controller.stop()
        diagnostics.finish()
    }
}
