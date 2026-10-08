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
            let displays = displayBounds()
            var perApp = [[WindowInfo]](repeating: [], count: apps.count)
            perApp.withUnsafeMutableBufferPointer { buffer in
                DispatchQueue.concurrentPerform(iterations: apps.count) { index in
                    buffer[index] = windows(of: apps[index], displays: displays)
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

    /// Global bounds of every active display, in the same top-left coordinates AX positions use.
    private static func displayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    /// Smallest side a real window can have; a titled window can't be shorter than its title bar.
    private static let minimumSide: CGFloat = 32

    /// Some apps keep helper windows that claim the standard subrole but are never meant to be seen,
    /// like Orion's "Orion Preview": 1×1 pt, tucked into a screen corner. Judge them by geometry.
    private static func isHelperWindow(position: CGPoint?, size: CGSize?, displays: [CGRect]) -> Bool {
        guard let position, let size else { return false }
        if size.width < minimumSide || size.height < minimumSide { return true }
        let frame = CGRect(origin: position, size: size)
        return !displays.isEmpty && !displays.contains { $0.intersects(frame) }
    }

    private static let windowAttributes = [
        kAXSubroleAttribute, kAXTitleAttribute, kAXMinimizedAttribute, kAXPositionAttribute, kAXSizeAttribute,
    ] as CFArray

    private static func windows(of app: AppRef, displays: [CGRect]) -> [WindowInfo] {
        let axApp = AXUIElementCreateApplication(app.pid)
        // A hung app must never stall the switcher.
        AXUIElementSetMessagingTimeout(axApp, 0.15)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let axWindows = value as? [AXUIElement] else { return [] }

        var result: [WindowInfo] = []
        for element in axWindows {
            // One IPC round-trip for all the attributes instead of one each.
            var valuesRef: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, windowAttributes, AXCopyMultipleAttributeOptions(rawValue: 0), &valuesRef) == .success,
                  let values = valuesRef as? [Any], values.count == 5 else { continue }

            let subrole = values[0] as? String
            guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { continue }
            guard !isHelperWindow(position: point(values[3]), size: size(values[4]), displays: displays) else { continue }
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

    private static func point(_ value: Any) -> CGPoint? {
        guard CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func size(_ value: Any) -> CGSize? {
        guard CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }
}
