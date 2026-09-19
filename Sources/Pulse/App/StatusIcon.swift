import AppKit

/// Pulse's menu bar icon: a screen outline with the island hanging from its top edge, the same
/// idea as the app icon, redrawn as a menu bar glyph.
///
/// Menu bar icons are *template* images: a black-and-alpha drawing that macOS tints to fit the
/// menu bar (white on dark, black on light, inverted when the menu is open). Only the alpha
/// channel matters. It's drawn as vectors at the 18 pt size macOS uses for menu bar glyphs, so it's
/// crisp on any display scale.
enum StatusIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: true) { bounds in
            draw(in: bounds)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Pulse"
        return image
    }

    static func draw(in bounds: NSRect) {
        NSColor.black.set()

        // The screen: a rounded outline, stroked at 1.5 pt like the system's own outline glyphs.
        let screen = NSRect(x: 1.25, y: 2.25, width: bounds.width - 2.5, height: bounds.height - 4.5)
        let outline = NSBezierPath(roundedRect: screen, xRadius: 3.25, yRadius: 3.25)
        outline.lineWidth = 1.5
        outline.stroke()

        // The island: flat along the screen's top edge, with a soft bowl underneath.
        let width: CGFloat = 9, depth: CGFloat = 4.5
        let left = bounds.midX - width / 2, right = bounds.midX + width / 2, top = screen.minY
        let island = NSBezierPath()
        island.move(to: NSPoint(x: left, y: top))
        island.line(to: NSPoint(x: right, y: top))
        island.curve(to: NSPoint(x: bounds.midX, y: top + depth),
                     controlPoint1: NSPoint(x: right, y: top + depth * 0.75),
                     controlPoint2: NSPoint(x: bounds.midX + width * 0.28, y: top + depth))
        island.curve(to: NSPoint(x: left, y: top),
                     controlPoint1: NSPoint(x: bounds.midX - width * 0.28, y: top + depth),
                     controlPoint2: NSPoint(x: left, y: top + depth * 0.75))
        island.close()
        island.fill()
    }
}
