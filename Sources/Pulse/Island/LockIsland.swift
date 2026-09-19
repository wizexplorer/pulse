import AppKit
import SwiftUI

/// The island on the lock screen: widens out of the notch with a lock beside it while the Mac is
/// locked. A successful unlock swings the shackle open, holds a beat, then folds the island back
/// into the notch. A failed attempt shakes the lock.
///
/// Its own small window, separate from the main island: it lives in the above-lock-screen space
/// (LockScreenSpace), exists only from lock until the fold has finished, and never takes input.
/// Motion is fitted to a frame-by-frame measurement of Alcove's lock screen (see Motion "Lock screen").
@MainActor
final class LockIslandController {
    private let state = IslandState()
    private let lock = LockGlyphModel()
    private lazy var shell = ShellAnimator(state: state)
    private var window: NSWindow?
    private var pendingWork: [DispatchWorkItem] = []

    func handle(_ event: LockScreenMonitor.Event) {
        switch event {
        case .locked: show()
        case .authenticationFailed: shake()
        case .authenticationSucceeded: unlock()
        case .unlocked: break
        }
    }

    // MARK: - Choreography

    private func show() {
        // Only where there's a hardware notch to grow out of: a fake notch on the lock screen of an
        // external display would look out of place.
        guard LockScreenSpace.isAvailable, let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else { return }
        cancelPendingWork()
        let notch = NotchGeometry.resolve(for: screen)
        state.notch = notch
        guard let window = makeWindowIfNeeded(for: notch) else { return }

        lock.reset()
        shell.set(IslandMetrics.closedSize(notch))
        window.orderFrontRegardless()

        // One frame at notch size first, so the growth is seen (as with the main island).
        after(0) { [self] in
            let target = IslandMetrics.lockedSize(notch)
            if Motion.reduceMotion {
                shell.set(target)
            } else {
                shell.animate(to: target, width: Motion.lockGrowSpring, height: Motion.lockGrowSpring)
            }
            withAnimation(Motion.contentIn) { lock.isShown = true }
        }
    }

    private func shake() {
        guard window != nil, !lock.isOpen, !Motion.reduceMotion else { return }
        lock.shakes += 1
    }

    private func unlock() {
        guard window != nil, !lock.isOpen else { return }
        cancelPendingWork()
        withAnimation(Motion.lockShackle) { lock.isOpen = true }

        after(Motion.lockOpenHold) { [self] in
            let closed = IslandMetrics.closedSize(state.notch)
            if Motion.reduceMotion {
                withAnimation(Motion.contentOut) { lock.isShown = false }
                shell.set(closed)
            } else {
                shell.animate(to: closed, width: Motion.lockCollapseSpring, height: Motion.lockCollapseSpring)
                withAnimation(Motion.lockGlyphOut) { lock.isShown = false }
            }
            // Back at exactly the notch's size and shape, so removing the window is invisible.
            after(Motion.lockCollapseSettle) { [self] in tearDown() }
        }
    }

    // MARK: - Window

    private func makeWindowIfNeeded(for notch: NotchGeometry) -> NSWindow? {
        let locked = IslandMetrics.lockedSize(notch)
        // A little room around the island so the collapse's undershoot never clips.
        let size = CGSize(width: (locked.width + 40).rounded(), height: (locked.height + 12).rounded())
        let frame = NSRect(x: (notch.centerX - size.width / 2).rounded(), y: notch.screenTop - size.height,
                           width: size.width, height: size.height)
        if let window {
            window.setFrame(frame, display: false)
            return window
        }

        let window = LockIslandWindow(contentRect: frame)
        let hosting = NSHostingView(rootView: LockIslandView(state: state, lock: lock))
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        window.contentView = hosting
        window.setFrame(frame, display: false)
        guard LockScreenSpace.adopt(window) else {
            Log.app.error("lock screen: couldn't move the island above the lock screen")
            return nil
        }
        shell.attach(to: hosting)
        self.window = window
        return window
    }

    private func tearDown() {
        window?.orderOut(nil)
        window = nil // freed while unlocked; rebuilt on the next lock
        lock.reset()
    }

    private func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        let item = DispatchWorkItem { MainActor.assumeIsolated(work) }
        pendingWork.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelPendingWork() {
        pendingWork.forEach { $0.cancel() }
        pendingWork.removeAll()
    }
}

/// Borderless, transparent, click-through, and allowed to be visible before login.
private final class LockIslandWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        canBecomeVisibleWithoutLogin = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class LockGlyphModel: ObservableObject {
    @Published var isShown = false
    @Published var isOpen = false
    /// Bumped once per failed attempt; each bump plays one shake.
    @Published var shakes = 0

    func reset() {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            isShown = false
            isOpen = false
        }
    }
}

private struct LockIslandView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var lock: LockGlyphModel

    var body: some View {
        let height = state.notch.size.height
        let shape = NotchShape(topRadius: IslandMetrics.closedTopRadius, bottomRadius: IslandMetrics.closedBottomRadius)
        ZStack(alignment: .topLeading) {
            shape.fill(Color.black)
            LockGlyph(size: IslandMetrics.lockGlyphSize(height), isOpen: lock.isOpen, shakes: lock.shakes)
                // Blurs in and out like the island's content, scaled down for a small glyph.
                .modifier(IslandContentEffect(progress: lock.isShown ? 1 : 0, reduceMotion: Motion.reduceMotion, maxBlur: 5))
                // Centered in the left wing, so it rides the left edge in and out.
                .position(x: IslandMetrics.closedTopRadius + IslandMetrics.lockWing(height) / 2, y: height / 2)
        }
        .frame(width: state.width, height: state.height, alignment: .topLeading)
        .clipShape(shape)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }
}

/// A padlock drawn as two parts, so the shackle can swing open in 3D: it turns 180° about a vertical
/// axis near the body's right side and lands to the right, as in SF Symbols' `lock.open.fill`.
/// Proportions measured from the reference (body 22×18 of a 22×32 glyph, shackle 68% of the body's
/// width, stroke 12%).
private struct LockGlyph: View {
    let size: CGFloat
    let isOpen: Bool
    let shakes: Int

    var body: some View {
        let bodyWidth = size * 0.69
        let bodyHeight = size * 0.5625
        let stroke = bodyWidth * 0.12
        let shackleWidth = bodyWidth * 0.68
        // Swing axis at 68% of the body's width, in the shackle's own coordinates.
        let axis = (0.68 - 0.16) / 0.68

        ZStack(alignment: .top) {
            Shackle(lineWidth: stroke)
                .frame(width: shackleWidth, height: size - bodyHeight + stroke) // legs tuck into the body
                .rotation3DEffect(.degrees(isOpen ? 180 : 0), axis: (x: 0, y: 1, z: 0),
                                  anchor: UnitPoint(x: axis, y: 0.5), perspective: 0.4)
            RoundedRectangle(cornerRadius: size * 0.09, style: .continuous)
                .frame(width: bodyWidth, height: bodyHeight)
                .offset(y: size - bodyHeight)
        }
        .frame(width: size, height: size, alignment: .top)
        // The open lock re-centers: the body steps left as the shackle lands to the right.
        .offset(x: isOpen ? -bodyWidth * 0.13 : 0)
        .foregroundStyle(.white)
        .keyframeAnimator(initialValue: CGFloat(0), trigger: shakes) { content, x in
            content.offset(x: x)
        } keyframes: { _ in
            let amplitude = size * 0.45
            let half = 1 / (2 * Motion.lockShakeFrequency)
            let decay = Motion.lockShakeDecay
            KeyframeTrack {
                CubicKeyframe(-amplitude, duration: half / 2)
                CubicKeyframe(amplitude * decay, duration: half)
                CubicKeyframe(-amplitude * pow(decay, 2), duration: half)
                CubicKeyframe(amplitude * pow(decay, 3), duration: half)
                CubicKeyframe(-amplitude * pow(decay, 4), duration: half)
                CubicKeyframe(amplitude * pow(decay, 5), duration: half)
                CubicKeyframe(0, duration: half / 2)
            }
        }
    }
}

/// An upside-down U: two legs and a semicircular top.
private struct Shackle: Shape {
    let lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let inset = lineWidth / 2
        let radius = (rect.width - lineWidth) / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset + radius))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.minY + inset + radius), radius: radius,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        return path.strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
    }
}
