import AppKit
import SwiftUI

/// Borderless, transparent, non-activating panel that sits above the menu bar (and full-screen apps).
///
/// Non-activating means showing it never steals focus from the app you are working in. It only
/// becomes key when the clipboard UI needs typed input, and even then the other app stays active.
final class IslandPanel: NSPanel {
    var allowsKey = false

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: IslandMetrics.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isFloatingPanel = true
        // Must come AFTER `isFloatingPanel`, which silently resets the level to `.floating` (3).
        // At level 3 the menu bar (24) and menu-bar tools like Ice (25) draw over the island.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { allowsKey }

    /// AppKit moves windows out from under the menu bar by default, which would push the island
    /// down by the menu bar's height. The island must sit flush with the top of the screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
    override var canBecomeMain: Bool { false }

    func setRootView<V: View>(_ view: V) {
        let hosting = NSHostingView(rootView: view)
        // The panel's size is fixed; never let SwiftUI resize the window during animations.
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        contentView = hosting
    }

    /// Pins the panel's top edge to the top of the screen, centered on the notch.
    func position(for notch: NotchGeometry) {
        let size = IslandMetrics.panelSize
        let origin = NSPoint(x: (notch.centerX - size.width / 2).rounded(), y: notch.screenTop - size.height)
        setFrame(NSRect(origin: origin, size: size), display: false)
    }
}
