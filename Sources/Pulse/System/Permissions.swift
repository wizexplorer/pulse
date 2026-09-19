import AppKit
import ApplicationServices

enum Permissions {
    /// Needed for: reading other apps' windows, focusing windows, event taps, and synthesizing ⌘V.
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Calls `handler` whenever the system's Accessibility allow-list changes. Event driven, so we
    /// never have to poll `AXIsProcessTrusted()` while waiting for the user to grant access.
    static func observeAccessibilityChanges(_ handler: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { _ in
            // The trust flag flips slightly after the notification is posted.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated { handler() }
            }
        }
    }
}
