import ServiceManagement

/// The "Launch at login" switch. A model object rather than view state because the
/// Command Line Tools lack the plugin behind SwiftUI's `@State` macro in the macOS 27 SDK.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    /// Shown under the switch when turning it on or off didn't simply work.
    @Published private(set) var message: String?

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            message = nil
        } catch {
            message = "Couldn't change the login item: \(error.localizedDescription)"
        }
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            message = "Allow Refresher in System Settings › General › Login Items."
        }
        refresh()
    }

    /// Picks up changes made in System Settings.
    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
