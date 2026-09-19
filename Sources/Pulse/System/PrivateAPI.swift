import AppKit
import ApplicationServices

/// Private WindowServer / HIServices entry points, resolved at runtime with `dlsym`.
///
/// Resolving lazily (rather than linking) means a future macOS that removes a symbol degrades us to
/// the public-API fallback instead of crashing at launch. These are the same calls used by AltTab,
/// yabai and Hammerspoon; there is no public API that can focus one specific window of another app.
enum PrivateAPI {
    private typealias AXGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private typealias GetProcessForPIDFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias SetFrontProcessFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private typealias PostEventRecordFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func symbol<T>(_ name: String, _ type: T.Type) -> T? {
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) // RTLD_DEFAULT
            ?? skyLight.flatMap({ dlsym($0, name) }) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    private static let axGetWindow = symbol("_AXUIElementGetWindow", AXGetWindowFn.self)
    private static let getProcessForPID = symbol("GetProcessForPID", GetProcessForPIDFn.self)
    private static let setFrontProcess = symbol("_SLPSSetFrontProcessWithOptions", SetFrontProcessFn.self)
    private static let postEventRecord = symbol("SLPSPostEventRecordTo", PostEventRecordFn.self)

    /// Maps an AX window element to its WindowServer id (used to join AX data with z-order).
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let axGetWindow else { return nil }
        var id: CGWindowID = 0
        guard axGetWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    /// Brings `windowID` of `pid` to the front and makes it key. Returns false if unavailable.
    static func focusWindow(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let getProcessForPID, let setFrontProcess, let postEventRecord else { return false }
        var psn = ProcessSerialNumber()
        guard getProcessForPID(pid, &psn) == noErr else { return false }
        let userGenerated: UInt32 = 0x200
        guard setFrontProcess(&psn, windowID, userGenerated) == .success else { return false }
        makeKeyWindow(&psn, windowID, post: postEventRecord)
        return true
    }

    /// Makes a window key by posting a synthetic mouse-down *record* addressed to the window id.
    /// Layout of the 0xF8-byte CGSEventRecord per CGSInternal/CGSEvent.h. Only the down half is sent
    /// and the location is far outside any window, so no control inside it is ever clicked.
    private static func makeKeyWindow(_ psn: inout ProcessSerialNumber, _ windowID: CGWindowID, post: PostEventRecordFn) {
        var bytes = [UInt8](repeating: 0, count: 0x100) // oversized & zeroed on purpose
        bytes[0x04] = 0xF8 // record length
        bytes[0x08] = 0x01 // kCGEventLeftMouseDown
        bytes[0x3A] = 0x10
        var id = windowID
        var location = CGPoint(x: 300_000, y: 300_000)
        withUnsafeBytes(of: &id) { bytes.replaceSubrange(0x3C ..< 0x3C + $0.count, with: $0) }
        withUnsafeBytes(of: &location) { bytes.replaceSubrange(0x20 ..< 0x20 + $0.count, with: $0) }
        bytes.withUnsafeMutableBufferPointer { buffer in
            _ = post(&psn, buffer.baseAddress!)
        }
    }
}
