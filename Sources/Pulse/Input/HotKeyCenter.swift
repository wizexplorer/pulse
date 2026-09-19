import Carbon.HIToolbox

/// Global hotkeys via Carbon's `RegisterEventHotKey`.
///
/// This is the cheapest way to listen for a shortcut on macOS: the WindowServer matches the key
/// combo itself and only wakes us when it is pressed, and the key is swallowed so the frontmost app
/// never sees it. No event tap, no per-keystroke work in our process.
@MainActor
final class HotKeyCenter {
    struct Token: Hashable {
        fileprivate let id: UInt32
    }

    static let shared = HotKeyCenter()

    private static let signature: OSType = 0x504C_5345 // 'PLSE'
    private var entries: [UInt32: (ref: EventHotKeyRef, handler: () -> Void)] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), pulseHotKeyHandler, 1, &spec, nil, &eventHandler)
    }

    /// - Parameters:
    ///   - keyCode: a `kVK_*` virtual key code.
    ///   - modifiers: Carbon modifier mask (`cmdKey`, `optionKey`, `shiftKey`, `controlKey`).
    /// - Returns: a token for `unregister`, or nil if the system refused the combination.
    @discardableResult
    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) -> Token? {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers),
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return nil }
        entries[id] = (ref, handler)
        return Token(id: id)
    }

    func unregister(_ token: Token) {
        guard let entry = entries.removeValue(forKey: token.id) else { return }
        UnregisterEventHotKey(entry.ref)
    }

    fileprivate func fire(_ id: UInt32) {
        entries[id]?.handler()
    }
}

/// Carbon delivers hotkey events on the main thread.
private func pulseHotKeyHandler(_: EventHandlerCallRef?, _ event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
    )
    guard status == noErr else { return status }
    MainActor.assumeIsolated { HotKeyCenter.shared.fire(hotKeyID.id) }
    return noErr
}
