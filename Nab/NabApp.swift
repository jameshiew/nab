import SwiftUI

@main
struct NabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Nab", systemImage: "tray") {
            Button("About Nab", action: showAbout)
            Divider()
            Button("Quit Nab") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
