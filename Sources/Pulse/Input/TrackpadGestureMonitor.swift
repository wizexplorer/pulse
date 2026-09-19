import AppKit
import PulseObjC

/// Detects a horizontal three-finger swipe on the trackpad.
///
/// Design (efficiency is the priority):
/// - Gesture events stream continuously while *any* finger touches the trackpad, so the work per
///   event is kept tiny: one- and two-finger events are dropped after a finger count.
/// - The taps live on the main run loop because AppKit can only decode touches (`NSEvent(cgEvent:)`)
///   on the main thread. Off the main thread it silently yields no touches. Hopping to main for
///   every event would cost more than simply running here, and the main thread is idle otherwise.
/// - Detection uses a LISTEN-ONLY tap: the WindowServer hands us a copy and moves on, so our process
///   can never add latency to the cursor or to scrolling.
/// - A second, ACTIVE tap exists only to swallow the gesture once it has become ours (so the app
///   under the cursor doesn't also react). It is enabled only while three fingers are down.
/// - Taps created later run earlier, so the absorbing tap is created first and the detecting tap
///   second: detection decides, then absorption applies that decision to the same event.
///
/// Requires Accessibility permission. For best results set Trackpad ▸ More Gestures ▸ "Swipe between
/// full-screen applications" to four fingers (or off), otherwise macOS also acts on the swipe.
final class TrackpadGestureMonitor: @unchecked Sendable {
    enum Direction { case left, right }

    // Set these before `start()`; they are invoked on the main thread.
    var onBegin: (@MainActor (Direction) -> Void)?
    var onStep: (@MainActor (Direction) -> Void)?
    var onEnd: (@MainActor () -> Void)?

    private var isRunning = false
    private var detectTap: CFMachPort?
    private var absorbTap: CFMachPort?
    private var loggedFirstEvent = false

    // State below is only touched on the main thread (the taps' run loop).
    private var absorbTapEnabled = false
    private var absorbing = false
    private var tracking = false
    private var triggered = false
    private var originX: CGFloat = 0
    private var originY: CGFloat = 0
    private var anchorX: CGFloat = 0

    /// Installs the taps. Returns false if they couldn't be created (no Accessibility access).
    @MainActor
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        isRunning = installTaps()
        return isRunning
    }

    private func installTaps() -> Bool {
        let mask = CGEventMask(1) << CGEventMask(NSEvent.EventType.gesture.rawValue)
        let info = Unmanaged.passUnretained(self).toOpaque()
        absorbTap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: absorbCallback, userInfo: info
        )
        detectTap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: detectCallback, userInfo: info
        )
        guard let absorbTap, let detectTap else {
            if let absorbTap { CFMachPortInvalidate(absorbTap) }
            if let detectTap { CFMachPortInvalidate(detectTap) }
            return false
        }
        CGEvent.tapEnable(tap: absorbTap, enable: false)
        for tap in [absorbTap, detectTap] {
            CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        }
        return true
    }

    // MARK: - Tap callbacks (main thread)

    fileprivate func detect(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let detectTap { CGEvent.tapEnable(tap: detectTap, enable: true) }
            return
        }
        process(event)
    }

    fileprivate func shouldAbsorb(type: CGEventType) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if absorbTapEnabled, let absorbTap { CGEvent.tapEnable(tap: absorbTap, enable: true) }
            return false
        }
        return absorbing
    }

    private func process(_ cgEvent: CGEvent) {
        guard let event = NSEvent(cgEvent: cgEvent) else { return }
        let touches = event.allTouches()
        if !loggedFirstEvent, !touches.isEmpty {
            loggedFirstEvent = true
            Log.input.info("first trackpad gesture event decoded: \(touches.count) touches")
        }
        // macOS interleaves spurious empty frames; they carry no information.
        guard !touches.isEmpty else { return }

        // Pass 1: count fingers only. One and two fingers (pointing, scrolling) are the hot path and
        // end here without reading a single position.
        var count = 0
        for touch in touches where touch.type == .indirect && NSTouch.Phase.touching.contains(touch.phase) {
            count += 1
        }
        guard count == Config.gestureFingerCount else {
            if tracking { endTracking() }
            return
        }

        // Pass 2: average position of the fingers.
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for touch in touches where touch.type == .indirect && NSTouch.Phase.touching.contains(touch.phase) {
            var position = CGPoint.zero
            // `normalizedPosition` raises for some forwarded touches (e.g. Universal Control).
            guard PulseTryObjC({ position = touch.normalizedPosition }) else { return }
            sumX += position.x
            sumY += position.y
        }

        let x = sumX / CGFloat(count)
        let y = sumY / CGFloat(count)
        guard tracking else {
            tracking = true
            triggered = false
            originX = x
            originY = y
            anchorX = x
            setAbsorbTapEnabled(true)
            return
        }

        if !triggered {
            let dx = x - originX
            let dy = y - originY
            guard abs(dx) >= Config.gestureTriggerDistance, abs(dx) > abs(dy) * 1.5 else { return }
            triggered = true
            absorbing = true
            anchorX = x
            let direction: Direction = dx > 0 ? .right : .left
            Log.input.info("three-finger swipe recognised")
            MainActor.assumeIsolated { onBegin?(direction) }
        } else {
            let dx = x - anchorX
            guard abs(dx) >= Config.gestureStepDistance else { return }
            anchorX = x
            let direction: Direction = dx > 0 ? .right : .left
            MainActor.assumeIsolated { onStep?(direction) }
        }
    }

    private func endTracking() {
        if triggered {
            MainActor.assumeIsolated { onEnd?() }
        }
        tracking = false
        triggered = false
        absorbing = false
        setAbsorbTapEnabled(false)
    }

    /// `tapEnable` is IPC to the WindowServer, so it is only called at gesture boundaries.
    private func setAbsorbTapEnabled(_ enabled: Bool) {
        guard enabled != absorbTapEnabled, let absorbTap else { return }
        absorbTapEnabled = enabled
        CGEvent.tapEnable(tap: absorbTap, enable: enabled)
    }
}

private func monitor(_ userInfo: UnsafeMutableRawPointer?) -> TrackpadGestureMonitor? {
    guard let userInfo else { return nil }
    return Unmanaged<TrackpadGestureMonitor>.fromOpaque(userInfo).takeUnretainedValue()
}

private func detectCallback(
    proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    monitor(userInfo)?.detect(type: type, event: event)
    return Unmanaged.passUnretained(event)
}

private func absorbCallback(
    proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    monitor(userInfo)?.shouldAbsorb(type: type) == true ? nil : Unmanaged.passUnretained(event)
}
