import AppKit
import Carbon.HIToolbox

/// Fallback for ⌥⇥ if the system ever refuses Option-only Carbon hotkeys (macOS 15.0 did).
///
/// An active keyboard tap sits in the path of every keystroke, so it is only created when the
/// hotkey route failed, and its callback does the minimum possible work before returning.
final class KeyboardTap: @unchecked Sendable {
    var onOptionTab: (@MainActor (_ reverse: Bool) -> Void)?

    private var tap: CFMachPort?

    func start() {
        guard tap == nil else { return }
        let mask = CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyboardTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap else { return }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Tab) else { return false }
        let flags = event.flags
        guard flags.contains(.maskAlternate), !flags.contains(.maskCommand), !flags.contains(.maskControl) else { return false }
        let reverse = flags.contains(.maskShift)
        MainActor.assumeIsolated { onOptionTab?(reverse) }
        return true
    }
}

private func keyboardTapCallback(
    proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<KeyboardTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}
