import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = ShelfController()
    private let diagnostics = DiagnosticsRecorder.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        diagnostics.start()
        NSApp.setActivationPolicy(.accessory)
        controller.start()
        diagnostics.record("application_ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        diagnostics.record("application_termination_started")
        controller.stop()
        diagnostics.finish()
    }
}
