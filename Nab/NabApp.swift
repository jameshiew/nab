import ServiceManagement
import SwiftUI

@main
struct NabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Nab", systemImage: "tray") {
            NabMenu()
        }

        Settings {
            SettingsView()
        }
    }
}

private struct NabMenu: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings...", action: showSettings)
            .keyboardShortcut(",")
        Divider()
        Button("About Nab", action: showAbout)
        Divider()
        Button("Quit Nab") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showSettings() {
        NSApp.activate()
        openSettings()
    }

    private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

private struct SettingsView: View {
    @State private var startsAtLogin = LoginItemService.isEnabled
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Toggle("Start at login", isOn: startAtLoginBinding)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 320)
        .onAppear(perform: refreshStartAtLogin)
    }

    private var startAtLoginBinding: Binding<Bool> {
        Binding {
            startsAtLogin
        } set: { isEnabled in
            setStartAtLogin(isEnabled)
        }
    }

    private func setStartAtLogin(_ isEnabled: Bool) {
        errorMessage = nil

        do {
            try LoginItemService.setEnabled(isEnabled)
            refreshStartAtLogin()
        } catch {
            startsAtLogin = LoginItemService.isEnabled
            errorMessage = error.localizedDescription
        }
    }

    private func refreshStartAtLogin() {
        startsAtLogin = LoginItemService.isEnabled
    }
}

private enum LoginItemService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status != .notRegistered else { return }
            try SMAppService.mainApp.unregister()
        }
    }
}
