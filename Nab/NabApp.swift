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
    @Environment(\.scenePhase) private var scenePhase

    @State private var loginItemState = LoginItemService.state
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Toggle("Start at login", isOn: startAtLoginBinding)
                .disabled(!loginItemState.isAvailable)

            switch loginItemState {
            case .requiresApproval:
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        "Nab needs your approval in System Settings before it can start "
                            + "automatically."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Button("Open Login Items Settings") {
                        LoginItemService.openSystemSettings()
                    }
                }
            case .unavailable:
                Text("Start at login is unavailable for this copy of Nab.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .disabled, .enabled:
                EmptyView()
            }

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
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshStartAtLogin()
        }
    }

    private var startAtLoginBinding: Binding<Bool> {
        Binding {
            loginItemState.isOn
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
            refreshStartAtLogin()
            errorMessage = error.localizedDescription
        }
    }

    private func refreshStartAtLogin() {
        loginItemState = LoginItemService.state
    }
}

enum LoginItemState: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    init(_ status: SMAppService.Status) {
        switch status {
        case .notRegistered:
            self = .disabled
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        case .notFound:
            self = .unavailable
        @unknown default:
            self = .unavailable
        }
    }

    var isOn: Bool {
        self == .enabled || self == .requiresApproval
    }

    var isAvailable: Bool {
        self != .unavailable
    }
}

private enum LoginItemService {
    static var state: LoginItemState {
        LoginItemState(SMAppService.mainApp.status)
    }

    static func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            guard state == .disabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard state == .enabled || state == .requiresApproval else { return }
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
