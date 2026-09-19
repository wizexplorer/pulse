import AppKit

/// Puts windows on the lock screen.
///
/// The lock screen is drawn by loginwindow on a WindowServer layer above every normal window level,
/// so no `NSWindow.level` can reach it. A private SkyLight *space* can: created once with an absolute
/// level of 400 (the layer macOS uses for notifications shown on the lock screen), any window moved
/// into it is composited above the lock screen. Technique from Lakr233/SkyLightWindow (MIT).
///
/// Resolved with `dlsym` like `PrivateAPI`: if a future macOS drops a symbol, `isAvailable` is false
/// and the lock screen island simply doesn't appear. Nothing else is affected.
@MainActor
enum LockScreenSpace {
    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias SpaceCreateFn = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevelFn = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpacesFn = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindowsFn = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    /// kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock: above the lock screen (300), below boot
    /// progress and VoiceOver.
    private static let aboveLockScreenLevel: Int32 = 400

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func symbol<T>(_ name: String, _ type: T.Type) -> T? {
        guard let skyLight, let pointer = dlsym(skyLight, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    private static let mainConnection = symbol("SLSMainConnectionID", MainConnectionFn.self)
    private static let spaceCreate = symbol("SLSSpaceCreate", SpaceCreateFn.self)
    private static let setAbsoluteLevel = symbol("SLSSpaceSetAbsoluteLevel", SpaceSetAbsoluteLevelFn.self)
    private static let showSpaces = symbol("SLSShowSpaces", ShowSpacesFn.self)
    private static let addWindows = symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", AddWindowsFn.self)

    static var isAvailable: Bool {
        mainConnection != nil && spaceCreate != nil && setAbsoluteLevel != nil && showSpaces != nil && addWindows != nil
    }

    /// Created on first use and kept for the app's lifetime: an empty space costs nothing.
    private static var space: (connection: Int32, id: Int32)? = {
        guard isAvailable, let mainConnection, let spaceCreate, let setAbsoluteLevel, let showSpaces else { return nil }
        let connection = mainConnection()
        let id = spaceCreate(connection, 1, 0)
        guard id != 0 else { return nil }
        _ = setAbsoluteLevel(connection, id, aboveLockScreenLevel)
        _ = showSpaces(connection, [id] as CFArray)
        return (connection, id)
    }()

    /// Moves `window` into the above-lock-screen space. Returns false if that isn't possible.
    /// (The call's own return value isn't a reliable error code, so only the space's existence counts.)
    @discardableResult
    static func adopt(_ window: NSWindow) -> Bool {
        guard let space, let addWindows else { return false }
        _ = addWindows(space.connection, space.id, [window.windowNumber] as CFArray, 7)
        return true
    }
}
