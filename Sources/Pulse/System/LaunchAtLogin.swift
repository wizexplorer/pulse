import Foundation
import ServiceManagement

/// Starting Pulse at login, via the system's login-item service (shows up in System Settings ▸
/// General ▸ Login Items, where the user can also turn it off).
enum LaunchAtLogin {
    private static let configuredKey = "LaunchAtLoginConfigured"

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("launch at login \(enabled ? "register" : "unregister") failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// On the installed app's first launch, turn launch-at-login on. Only once: if the user turns
    /// it off later, that choice sticks. Development builds (run from the repo) never register, so
    /// the login item always points at the copy in /Applications.
    static func enableOnFirstInstalledLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: configuredKey),
              Bundle.main.bundleURL.path.hasPrefix("/Applications/") else { return }
        setEnabled(true)
        defaults.set(true, forKey: configuredKey)
    }
}
