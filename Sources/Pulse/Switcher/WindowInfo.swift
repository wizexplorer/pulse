import AppKit
import ApplicationServices

struct WindowInfo: Identifiable, @unchecked Sendable {
    let id: String
    let windowID: CGWindowID?
    let pid: pid_t
    let element: AXUIElement
    let appName: String
    let title: String
    let icon: NSImage
    let isMinimized: Bool
    let isAppHidden: Bool

    var displayTitle: String { title.isEmpty ? appName : title }
}
