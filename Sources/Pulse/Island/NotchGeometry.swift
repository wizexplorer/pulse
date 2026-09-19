import AppKit

/// Where the (real or simulated) notch is on a given screen, in global screen coordinates.
struct NotchGeometry: Equatable {
    var size: CGSize
    var centerX: CGFloat
    var screenTop: CGFloat
    var hasHardwareNotch: Bool

    static let fallback = NotchGeometry(size: CGSize(width: 190, height: 32), centerX: 0, screenTop: 0, hasHardwareNotch: false)

    static func resolve(for screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            // The notch is whatever the two unobscured menu-bar areas leave between them.
            let width = frame.width - left.width - right.width
            return NotchGeometry(
                size: CGSize(width: width, height: screen.safeAreaInsets.top),
                centerX: frame.minX + left.width + width / 2,
                screenTop: frame.maxY,
                hasHardwareNotch: true
            )
        }
        // No notch: grow out of a virtual one the height of the menu bar.
        let menuBarHeight = frame.maxY - screen.visibleFrame.maxY
        return NotchGeometry(
            size: CGSize(width: 190, height: menuBarHeight > 0 ? menuBarHeight : 32),
            centerX: frame.midX,
            screenTop: frame.maxY,
            hasHardwareNotch: false
        )
    }

    /// The screen the island should appear on: the one showing the active menu bar.
    static var activeScreen: NSScreen? { NSScreen.main ?? NSScreen.screens.first }
}

/// Island dimensions per mode. Content is laid out against these fixed sizes, so only the shell
/// animates, never the layout inside it.
enum IslandMetrics {
    static let closedTopRadius: CGFloat = 6
    static let closedBottomRadius: CGFloat = 10
    static let openTopRadius: CGFloat = 26 // the "ears" flaring into the top edge
    static let openBottomRadius: CGFloat = 30
    /// How far below the notch the island must extend before its corners are fully open-sized.
    static let cornerGrowthDistance: CGFloat = 80

    /// The panel is a fixed transparent canvas large enough for every mode; the island draws inside it.
    static let panelSize = CGSize(width: 820, height: 620)

    static let switcherWidth: CGFloat = 540 // window panel width (was 460)
    static let switcherRowHeight: CGFloat = 44
    static let switcherRowSpacing: CGFloat = 2
    static let maxVisibleSwitcherRows = 6
    /// Rows kept between the selection and the edge of the list before it scrolls (the "bottom third").
    static let switcherScrollMargin = 2

    static let clipboardSize = CGSize(width: 720, height: 420)

    static let contentInset: CGFloat = 12
    /// Gap between the switcher's last row and the island's bottom edge.
    static let switcherBottomInset: CGFloat = 10

    static func closedSize(_ notch: NotchGeometry) -> CGSize {
        CGSize(width: notch.size.width + 2 * closedTopRadius, height: notch.size.height)
    }

    static func switcherListHeight(rows: Int) -> CGFloat {
        let visible = CGFloat(min(max(rows, 1), maxVisibleSwitcherRows))
        return visible * switcherRowHeight + (visible - 1) * switcherRowSpacing
    }

    static func switcherSize(_ notch: NotchGeometry, rows: Int) -> CGSize {
        CGSize(width: switcherWidth, height: notch.size.height + switcherListHeight(rows: rows) + switcherBottomInset)
    }

    static func clipboardSize(_ notch: NotchGeometry) -> CGSize {
        CGSize(width: clipboardSize.width, height: notch.size.height + clipboardSize.height)
    }
}
