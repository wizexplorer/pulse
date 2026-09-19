import AppKit
import ApplicationServices

/// Builds the window list on demand, only when the switcher opens.
///
/// Nothing is tracked in the background: no AX observers, no polling. Recency comes for free from
/// the WindowServer's z-order (front-to-back = most recently used), which is joined with per-app
/// Accessibility data gathered concurrently. Typical cost: a few milliseconds, well inside the
/// island's opening animation.
enum WindowEnumerator {
    private struct AppRef: @unchecked Sendable {
        let pid: pid_t
        let name: String
        let icon: NSImage
        let isHidden: Bool
        let rank: Int
    }

    private static let queue = DispatchQueue(label: "Pulse.WindowEnumerator", qos: .userInteractive)
    private static var iconCache: [String: NSImage] = [:] // main thread only

    @MainActor
    static func snapshot(completion: @escaping @MainActor ([WindowInfo]) -> Void) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps: [AppRef] = NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, app.processIdentifier != ownPID, !app.isTerminated else { return nil }
            return AppRef(
                pid: app.processIdentifier,
                name: app.localizedName ?? "",
                icon: icon(for: app),
                isHidden: app.isHidden,
                rank: AppActivationTracker.shared.rank(of: app.processIdentifier)
            )
        }

        queue.async {
            let zOrder = onScreenZOrder()
            var perApp = [[WindowInfo]](repeating: [], count: apps.count)
            perApp.withUnsafeMutableBufferPointer { buffer in
                DispatchQueue.concurrentPerform(iterations: apps.count) { index in
                    buffer[index] = windows(of: apps[index])
                }
            }

            var entries: [(window: WindowInfo, z: Int, appRank: Int, order: Int)] = []
            for (appIndex, windows) in perApp.enumerated() {
                for (order, window) in windows.enumerated() {
                    let z = window.windowID.flatMap { zOrder[$0] } ?? Int.max
                    entries.append((window, z, apps[appIndex].rank, order))
                }
            }
            entries.sort { a, b in
                if a.z != b.z { return a.z < b.z }
                if a.appRank != b.appRank { return a.appRank < b.appRank }
                return a.order < b.order
            }
            let result = entries.map(\.window)
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(result) } }
        }
    }

    @MainActor
    private static func icon(for app: NSRunningApplication) -> NSImage {
        let key = app.bundleIdentifier ?? app.bundleURL?.path ?? "\(app.processIdentifier)"
        if let cached = iconCache[key] { return cached }
        let icon = (app.icon?.copy() as? NSImage) ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)!
        // Pin a small size so rows never rasterize the 1024px representation.
        icon.size = NSSize(width: 32, height: 32)
        iconCache[key] = icon
        return icon
    }

    /// Front-to-back order of normal (layer 0) on-screen windows. Needs no permissions.
    private static func onScreenZOrder() -> [CGWindowID: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var order: [CGWindowID: Int] = [:]
        order.reserveCapacity(list.count)
        for (index, info) in list.enumerated() {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? UInt32 else { continue }
            order[number] = index
        }
        return order
    }

    private static let windowAttributes = [kAXSubroleAttribute, kAXTitleAttribute, kAXMinimizedAttribute] as CFArray

    private static func windows(of app: AppRef) -> [WindowInfo] {
        let axApp = AXUIElementCreateApplication(app.pid)
        // A hung app must never stall the switcher.
        AXUIElementSetMessagingTimeout(axApp, 0.15)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let axWindows = value as? [AXUIElement] else { return [] }

        var result: [WindowInfo] = []
        for element in axWindows {
            // One IPC round-trip for all three attributes instead of three.
            var valuesRef: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, windowAttributes, AXCopyMultipleAttributeOptions(rawValue: 0), &valuesRef) == .success,
                  let values = valuesRef as? [Any], values.count == 3 else { continue }

            let subrole = values[0] as? String
            guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { continue }
            let title = values[1] as? String ?? ""
            let minimized = values[2] as? Bool ?? false
            let windowID = PrivateAPI.windowID(of: element)

            result.append(WindowInfo(
                id: windowID.map { "w\($0)" } ?? "p\(app.pid)-\(CFHash(element))",
                windowID: windowID,
                pid: app.pid,
                element: element,
                appName: app.name,
                title: title,
                icon: app.icon,
                isMinimized: minimized,
                isAppHidden: app.isHidden
            ))
        }
        return result
    }
}
