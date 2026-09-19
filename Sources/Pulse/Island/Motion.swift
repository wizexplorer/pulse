import AppKit
import SwiftUI

/// Every animation curve lives here so the whole app moves with one "voice".
///
/// Rules this follows (see plans/ for the reasoning):
/// - The shell (the black island) moves on springs, because springs retarget from the live value
///   when interrupted. It bounces only when a gesture carried momentum (a three-finger swipe). A
///   keypress gets just a hint of the Island's overshoot. Closing is the system's response, so it
///   is faster than opening and never bounces.
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

    static var open: Animation { reduceMotion ? fade : .spring(duration: 0.3, bounce: 0.1) }
    static var openFromSwipe: Animation { reduceMotion ? fade : .spring(duration: 0.36, bounce: 0.2) }
    static var resize: Animation { reduceMotion ? fade : .spring(duration: 0.34, bounce: 0.08) }
    static var close: Animation { reduceMotion ? fade : .spring(duration: 0.3, bounce: 0) }

    /// How long to keep the panel on screen after a close begins, so the spring can settle.
    static let closeSettleTime: TimeInterval = 0.34

    // MARK: Content

    static var contentIn: Animation { strongEaseOut(0.2).delay(reduceMotion ? 0 : 0.03) }
    static let contentOut = strongEaseOut(0.1)

    /// A list's selection highlight sliding to the next row.
    static var selection: Animation? { reduceMotion ? nil : .spring(duration: 0.26, bounce: 0.14) }

    /// A list sliding to keep the selection in view.
    static var listScroll: Animation? { reduceMotion ? nil : strongEaseOut(0.16) }

    /// Press feedback on rows: the press is the deliberate phase, the release is the system snapping back.
    static let pressIn = strongEaseOut(0.14)
    static let pressOut = strongEaseOut(0.08)

    /// cubic-bezier(0.23, 1, 0.32, 1): starts fast, so motion responds the instant it begins.
    static func strongEaseOut(_ duration: TimeInterval) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }

    private static let fade = strongEaseOut(0.2)
}

/// Blur + scale + fade used for content entering and leaving the island (fade only under Reduce Motion).
struct IslandContentEffect: ViewModifier {
    let progress: Double
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .blur(radius: reduceMotion ? 0 : (1 - progress) * 4)
            .scaleEffect(reduceMotion ? 1 : 0.96 + 0.04 * progress, anchor: .top)
    }
}

extension AnyTransition {
    static var islandContent: AnyTransition {
        let reduce = Motion.reduceMotion
        let hidden = IslandContentEffect(progress: 0, reduceMotion: reduce)
        let shown = IslandContentEffect(progress: 1, reduceMotion: reduce)
        return .asymmetric(
            insertion: .modifier(active: hidden, identity: shown).animation(Motion.contentIn),
            removal: .modifier(active: hidden, identity: shown).animation(Motion.contentOut)
        )
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
