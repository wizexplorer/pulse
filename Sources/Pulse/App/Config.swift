import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Tunables in one place. Promote to UserDefaults-backed settings once a preferences UI exists.
enum Config {
    // MARK: Hotkeys (Carbon virtual key codes + modifier masks)

    /// ⌃⌘V. ⇧⌘V would steal "Paste and Match Style" from most apps, and ⌥⌘V is Finder's "Move Here".
    static let clipboardHotKey = (keyCode: kVK_ANSI_V, modifiers: controlKey | cmdKey)

    // MARK: Clipboard

    static let clipboardHistoryLimit = 500
    /// NSPasteboard has no change notification, so we poll `changeCount` (a single cheap IPC).
    /// The generous leeway lets the kernel coalesce our wakeups with other timers.
    static let clipboardPollInterval: DispatchTimeInterval = .milliseconds(750)
    static let clipboardPollLeeway: DispatchTimeInterval = .milliseconds(400)
    static let maxImageBytes = 50 * 1024 * 1024
    static let maxTextLength = 1_000_000
    /// Never record copies made while one of these apps is frontmost.
    static let ignoredSourceBundleIDs: Set<String> = [
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
    ]

    // MARK: Trackpad

    static let trackpadGesturesEnabled = true
    static let gestureFingerCount = 3
    /// Fraction of the trackpad width the fingers must travel before the switcher opens.
    static let gestureTriggerDistance: CGFloat = 0.06
    /// Further travel needed for each additional selection step while the switcher is open.
    static let gestureStepDistance: CGFloat = 0.07
    static let hapticFeedback = true
}
