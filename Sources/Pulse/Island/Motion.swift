import AppKit
import QuartzCore
import SwiftUI

/// Every animation curve lives here so the whole app moves with one "voice".
///
/// Rules this follows (see plans/ for the reasoning):
/// - The shell (the black island) moves on springs, because springs retarget from the live value
///   when interrupted. It bounces only when a gesture carried momentum (a three-finger swipe). A
///   keypress gets just a hint of the Island's overshoot.
///
/// Values below are fitted to frame-by-frame measurements of a reference notch app the owner likes
/// (notification, call and calendar transitions, measured at 60 fps):
/// - Opening: width and height ride ONE spring (~0.4 s, bounce ~0.35): target reached in ~200 ms,
///   ~10% overshoot, settled by ~500 ms.
/// - Closing: the parts come apart. The sides lead (target in ~80–125 ms, springy), and the bottom
///   edge follows smoothly with almost no bounce (done at ~280 ms). Content is gone before the shell moves.
/// - Content fades in with a strong ease-out, readable within about 200 ms, and leaves faster than
///   it arrives.
/// - In both lists (window switcher and clipboard), the selection highlight slides from row to row
///   on ⇥/↑↓, and the list slides to keep the selection in view. That's a deliberate product
///   decision: the owner prefers the glide to an instant jump, even though the review-animations
///   rules say keyboard navigation shouldn't animate.
/// - Reduce Motion replaces all movement with short cross-fades.
enum Motion {
    /// System Settings ▸ Accessibility ▸ Display ▸ Reduce motion. Read live, so a change applies
    /// on the next open.
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: Shell

    // Shell size: independent width/height springs, run by ShellAnimator.
    /// Open: ~5% overshoot (bounce 0.32), at size by ~190 ms.
    static let openSpring = SpringSpec(duration: 0.38, bounce: 0.32)
    static let resizeSpring = SpringSpec(duration: 0.4, bounce: 0.33)
    /// Close: over-damped springs (negative bounce) so the start stays responsive but the final
    /// approach into the notch lingers. Sides lead slightly (50% at ~98 ms, 98% at ~403 ms)...
    static let closeWidthSpring = SpringSpec(duration: 0.34, bounce: -0.15)
    /// ...the bottom edge follows (50% at ~115 ms, 98% at ~473 ms).
    static let closeHeightSpring = SpringSpec(duration: 0.4, bounce: -0.15)

    // Corners and content (SwiftUI animations), matched to the shell's springs.
    static var open: Animation { reduceMotion ? fade : .spring(duration: 0.38, bounce: 0.32) }
    static var resize: Animation { reduceMotion ? fade : .spring(duration: 0.4, bounce: 0.33) }
    /// Corners follow the bottom edge when closing.
    static var closeCorners: Animation { reduceMotion ? fade : .spring(duration: 0.5, bounce: 0.1) }
    static var close: Animation { reduceMotion ? fade : closeCorners }

    /// How long to keep the panel on screen after a close begins, so the slowest part settles
    /// before the panel is ordered out.
    /// Close travel the springs above were tuned on (the 6-row window panel). Farther travel gets a
    /// proportionally quicker spring, so a bigger panel (the clipboard) doesn't feel slower to close.
    static let closeReferenceWidthTravel: CGFloat = 343
    static let closeReferenceHeightTravel: CGFloat = 284

    static let closeSettleTime: TimeInterval = 0.72

    // MARK: Content

    /// Content arrives early and blurred, then sharpens (reference: visible ~120 ms in, sharp by ~350 ms).
    static var contentIn: Animation { strongEaseOut(reduceMotion ? 0.2 : 0.34) }
    /// Content leaving: a quick blur-out, done well before the shell has closed.
    static let contentOut = strongEaseOut(0.14)

    /// A list's selection highlight sliding to the next row.
    static var selection: Animation? { reduceMotion ? nil : .spring(duration: 0.26, bounce: 0.14) }

    /// A list sliding to keep the selection in view (windows past the 6th, clipboard items past the
    /// fold). Driven by AppKit, not SwiftUI (see ListScroller), so it's an NSAnimationContext
    /// duration + curve: an unhurried ease-in-out that glides the next row in.
    static let listScrollDuration: TimeInterval = 0.4
    static let listScrollTiming = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)

    /// Press feedback on rows: the press is the deliberate phase, the release is the system snapping back.
    static let pressIn = strongEaseOut(0.14)
    static let pressOut = strongEaseOut(0.08)

    /// cubic-bezier(0.23, 1, 0.32, 1): starts fast, so motion responds the instant it begins.
    static func strongEaseOut(_ duration: TimeInterval) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }

    private static let fade = strongEaseOut(0.2)
}

/// Fade + blur for content entering and leaving the island (fade only under Reduce Motion).
/// Animatable, so `progress` itself is interpolated and the opacity/blur mapping below holds at
/// every frame.
struct IslandContentEffect: ViewModifier, Animatable {
    var progress: Double
    let reduceMotion: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            // Opaque early (by ~45% of the way), then the blur does the rest: content is laid out at
            // full size from the start and simply comes into focus, as in the reference.
            .opacity(reduceMotion ? progress : min(1, progress * 2.2))
            .blur(radius: reduceMotion ? 0 : (1 - progress) * 16)
    }
}

/// Rows that respond on pointer-down: a slight press-in while held, and the action on release.
struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let reduce = Motion.reduceMotion
        return configuration.label
            .scaleEffect(pressed && !reduce ? 0.98 : 1)
            // Reduce Motion keeps the feedback, just without movement.
            .opacity(pressed && reduce ? 0.85 : 1)
            .animation(pressed ? Motion.pressIn : Motion.pressOut, value: pressed)
    }
}
