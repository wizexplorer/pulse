import AppKit
import ApplicationServices

enum WindowFocuser {
    /// AX calls can block on a busy app, so focusing happens off the main thread.
    private static let queue = DispatchQueue(label: "Pulse.WindowFocuser", qos: .userInteractive)

    static func focus(_ window: WindowInfo) {
        queue.async {
            let element = window.element
            AXUIElementSetMessagingTimeout(element, 0.5)
            if window.isMinimized {
                AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            let app = NSRunningApplication(processIdentifier: window.pid)
            if window.isAppHidden { app?.unhide() }

            let focused = window.windowID.map { PrivateAPI.focusWindow(pid: window.pid, windowID: $0) } ?? false
            if !focused {
                // Public-API fallback: activate the app, then make this its main window.
                AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
                DispatchQueue.main.async { app?.activate() }
            }
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
    }
}
