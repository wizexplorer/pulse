import SwiftUI

/// The island silhouette: flush with the top edge of the screen, with concave "ears" flaring into the
/// menu bar at the top corners (like the hardware notch) and convex rounded corners at the bottom.
/// Both radii are animatable, so the shape morphs smoothly between the notch and the expanded island.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4, rect.height / 2)
        let bottom = min(bottomRadius, (rect.width - 2 * top) / 2, rect.height - top)
        let left = rect.minX + top
        let right = rect.maxX - top

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Top-left ear (concave).
        path.addQuadCurve(to: CGPoint(x: left, y: rect.minY + top), control: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: rect.maxY - bottom))
        // Bottom-left corner (convex, continuous-ish curvature via cubic).
        path.addCurve(
            to: CGPoint(x: left + bottom, y: rect.maxY),
            control1: CGPoint(x: left, y: rect.maxY - bottom * 0.45),
            control2: CGPoint(x: left + bottom * 0.45, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: right - bottom, y: rect.maxY))
        // Bottom-right corner.
        path.addCurve(
            to: CGPoint(x: right, y: rect.maxY - bottom),
            control1: CGPoint(x: right - bottom * 0.45, y: rect.maxY),
            control2: CGPoint(x: right, y: rect.maxY - bottom * 0.45)
        )
        path.addLine(to: CGPoint(x: right, y: rect.minY + top))
        // Top-right ear (concave).
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
