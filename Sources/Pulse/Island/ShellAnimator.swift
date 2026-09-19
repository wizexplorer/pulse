import AppKit
import QuartzCore
import SwiftUI

/// A spring described the way SwiftUI describes them: perceptual duration + bounce.
struct SpringSpec {
    var duration: Double
    var bounce: Double

    /// Shortens the spring for travel beyond `reference` (by the square root of the ratio, never
    /// below 75%), so the same motion covering more ground still finishes in about the same time.
    /// Shorter travel keeps the tuned timing.
    func scaled(forDistance distance: CGFloat, reference: CGFloat) -> SpringSpec {
        guard distance > reference, reference > 0 else { return self }
        let factor = max(0.75, (Double(reference) / Double(distance)).squareRoot())
        return SpringSpec(duration: duration * factor, bounce: bounce)
    }

    fileprivate var stiffness: Double { pow(2 * .pi / duration, 2) }
    fileprivate var damping: Double { 4 * .pi * (1 - bounce) / duration }
}

/// Drives the island shell's width and height on two *independent* springs.
///
/// SwiftUI animates a view's frame as one unit: if width and height change in the same update, one
/// animation wins for both, so "the sides lead, the bottom follows" is impossible through
/// `withAnimation`. Here each axis is its own damped spring, integrated once per display frame and
/// written straight into `IslandState` with animations disabled. Retargeting mid-flight keeps each
/// spring's current velocity, so interrupting an open with a close (or vice versa) never jumps.
///
/// Cost: the display link only runs while a spring is moving (about half a second per open or
/// close) and is invalidated the moment both settle.
@MainActor
final class ShellAnimator: NSObject {
    private struct Axis {
        var value: Double
        var velocity: Double = 0
        var target: Double
        var spec = SpringSpec(duration: 0.3, bounce: 0)

        var isResting: Bool { abs(value - target) < 0.2 && abs(velocity) < 2 }

        mutating func step(_ dt: Double) {
            // Semi-implicit Euler: stable for UI springs at display-frame substeps.
            let acceleration = -spec.stiffness * (value - target) - spec.damping * velocity
            velocity += acceleration * dt
            value += velocity * dt
        }
    }

    private let state: IslandState
    private weak var hostView: NSView?
    private var width: Axis
    private var height: Axis
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    init(state: IslandState) {
        self.state = state
        width = Axis(value: state.width, target: state.width)
        height = Axis(value: state.height, target: state.height)
    }

    /// The view whose display drives the frame clock (the panel's content view).
    func attach(to view: NSView) {
        hostView = view
    }

    /// Jumps to a size with no motion.
    func set(_ size: CGSize) {
        stop()
        width = Axis(value: size.width, target: size.width)
        height = Axis(value: size.height, target: size.height)
        write()
    }

    /// Springs each axis toward the target on its own spec, keeping any velocity already in flight.
    func animate(to size: CGSize, width widthSpec: SpringSpec, height heightSpec: SpringSpec) {
        width.target = size.width
        width.spec = widthSpec
        height.target = size.height
        height.spec = heightSpec
        guard !(width.isResting && height.isResting) else {
            write()
            return
        }
        start()
    }

    // MARK: - Frame clock

    private func start() {
        guard link == nil, let view = hostView else { return }
        // Take the first step now rather than waiting a vsync for the link's first tick: that
        // removed a frame of dead time between the trigger and visible motion.
        advance(by: 1.0 / 60)
        write()
        lastTimestamp = nil
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = min(now - (lastTimestamp ?? now - 1.0 / 60), 1.0 / 30)
        lastTimestamp = now

        advance(by: dt)
        if width.isResting && height.isResting {
            width.value = width.target
            width.velocity = 0
            height.value = height.target
            height.velocity = 0
            stop()
        }
        write()
    }

    private func advance(by dt: Double) {
        let substeps = 4
        for _ in 0..<substeps {
            width.step(dt / Double(substeps))
            height.step(dt / Double(substeps))
        }
    }

    private func write() {
        var transaction = Transaction()
        transaction.disablesAnimations = true // the springs above are the animation
        withTransaction(transaction) {
            state.width = width.value
            state.height = height.value
        }
    }
}
