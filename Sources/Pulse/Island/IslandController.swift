import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Owns the panel and orchestrates presenting / dismissing the island and the input sessions that
/// drive each mode. Everything here is event driven: when the island is closed, the panel is ordered
/// out and no monitors, timers or temporary hotkeys exist.
@MainActor
final class IslandController {
    let state = IslandState()
    let switcher = SwitcherModel()
    let clipboard: ClipboardModel

    private let panel = IslandPanel()
    private var hideWork: DispatchWorkItem?
    /// Bumped on every present/dismiss, so a deferred open can't land after a newer dismiss.
    private var presentationID = 0
    private var outsideClickMonitor: Any?

    // Switcher session
    private enum SwitcherTrigger { case keyboard, gesture, pointer }
    private var switcherTrigger: SwitcherTrigger?
    private var modifierMonitor: Any?
    /// Fallback open, in case the window list is slow to arrive.
    private var pendingSwitcherOpen: DispatchWorkItem?
    private var sessionHotKeys: [HotKeyCenter.Token] = []

    // Clipboard session
    private var clipboardTarget: NSRunningApplication?

    /// Called on every presentation; the app uses it to start permission-gated features late.
    var onPresent: (() -> Void)?

    init(clipboard: ClipboardModel) {
        self.clipboard = clipboard
        panel.setRootView(IslandRootView(
            state: state,
            switcher: switcher,
            clipboard: clipboard,
            onBackgroundTap: { [weak self] in self?.dismiss() }
        ))
        switcher.onLoaded = { [weak self] in
            guard let self else { return }
            if self.pendingSwitcherOpen != nil { self.openPendingSwitcher() } else { self.resizeForCurrentMode() }
        }
        switcher.onCommit = { [weak self] window in self?.finishSwitch(to: window) }
        switcher.onCancel = { [weak self] in self?.dismiss() }
        clipboard.onChoose = { [weak self] item, paste in self?.finishClipboard(with: item, paste: paste) }
        clipboard.onCancel = { [weak self] in self?.dismiss() }
    }

    // MARK: - Presentation

    private func present(_ mode: IslandMode, animation: Animation? = nil) {
        onPresent?()
        hideWork?.cancel()
        hideWork = nil
        presentationID += 1
        let id = presentationID

        let wasVisible = panel.isVisible
        if !wasVisible, let screen = NotchGeometry.activeScreen {
            // Start as an exact copy of the hardware notch, so the island appears to grow out of it.
            let notch = NotchGeometry.resolve(for: screen)
            state.notch = notch
            state.size = IslandMetrics.closedSize(notch)
            panel.position(for: notch)
        }

        panel.allowsKey = (mode == .clipboard)
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        if mode == .clipboard { panel.makeKey() }
        installOutsideClickMonitor()

        let apply = { [self] in
            guard id == presentationID else { return }
            let target = targetSize(for: mode)
            // Reduce Motion: the shell never grows on screen. It takes its final size up front and fades in.
            if Motion.reduceMotion { state.size = target }
            withAnimation(state.isOpen ? Motion.resize : (animation ?? Motion.open)) {
                state.mode = mode
                state.size = target
            }
        }
        // Give a freshly ordered-in panel one frame at notch size before springing open.
        if wasVisible { apply() } else { DispatchQueue.main.async { MainActor.assumeIsolated(apply) } }
    }

    func dismiss() {
        guard state.isOpen || panel.isVisible else { return }
        presentationID += 1
        endSwitcherSession()
        removeOutsideClickMonitor()
        clipboardTarget = nil

        if panel.isKeyWindow {
            // Hand keyboard focus straight back to the app underneath, without waiting for the
            // close animation: re-ordering a panel that can't become key drops its key status.
            panel.allowsKey = false
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
        panel.allowsKey = false
        panel.ignoresMouseEvents = true

        withAnimation(Motion.close) {
            state.mode = .idle
            // Reduce Motion: keep the size and let the shell fade out instead of shrinking.
            if !Motion.reduceMotion { state.size = IslandMetrics.closedSize(state.notch) }
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.state.isOpen else { return }
            self.panel.orderOut(nil)
            self.switcher.reset()
            self.clipboard.didDismiss()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Motion.closeSettleTime, execute: work)
    }

    private func targetSize(for mode: IslandMode) -> CGSize {
        switch mode {
        case .idle: IslandMetrics.closedSize(state.notch)
        case .switcher: IslandMetrics.switcherSize(state.notch, rows: switcher.rowCountForLayout)
        case .clipboard: IslandMetrics.clipboardSize(state.notch)
        }
    }

    private func resizeForCurrentMode() {
        guard state.isOpen else { return }
        let size = targetSize(for: state.mode)
        guard size != state.size else { return }
        if Motion.reduceMotion {
            state.size = size
        } else {
            withAnimation(Motion.resize) { state.size = size }
        }
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        // Global monitors only see events destined for other apps, i.e. clicks outside the island.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    private func removeOutsideClickMonitor() {
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor) }
        outsideClickMonitor = nil
    }

    // MARK: - Window switcher

    /// ⌥⇥ / ⌥⇧⇥. The first press opens the switcher on the previous window; further presses (while ⌥
    /// is held) step through the list, and releasing ⌥ switches.
    func switcherHotKey(reverse: Bool) {
        let step = reverse ? -1 : 1
        if state.mode == .switcher {
            switcher.step(step)
            return
        }
        guard NSEvent.modifierFlags.contains(.option) else {
            // ⌥ already released (a quick tap): switch straight away without showing anything,
            // like ⌘⇥ does.
            switcher.quickSwitch(step: step)
            return
        }
        beginSwitcher(trigger: .keyboard, initialStep: step)
    }

    /// Opened from the menu bar: stays open until a window is picked or the island is dismissed.
    func showSwitcher() {
        guard state.mode != .switcher else { return }
        beginSwitcher(trigger: .pointer, initialStep: 0)
    }

    func switcherGestureBegan(_ direction: TrackpadGestureMonitor.Direction) {
        if state.mode == .switcher {
            switcher.step(direction == .right ? 1 : -1)
        } else {
            beginSwitcher(trigger: .gesture, initialStep: direction == .right ? 1 : -1)
        }
        haptic()
    }

    func switcherGestureStepped(_ direction: TrackpadGestureMonitor.Direction) {
        guard state.mode == .switcher else { return }
        switcher.step(direction == .right ? 1 : -1)
        haptic()
    }

    func switcherGestureEnded() {
        guard state.mode == .switcher, switcherTrigger == .gesture else { return }
        switcher.commit()
    }

    private func beginSwitcher(trigger: SwitcherTrigger, initialStep: Int) {
        endSwitcherSession()
        switcherTrigger = trigger
        installSwitcherSessionInput(for: trigger)
        switcher.begin(initialStep: initialStep)
        // Open once the window list is in (usually 5–120 ms), so the island springs straight to its
        // final size. A resize that lands in the first frames of the open spring gets lost, which
        // left the very first switcher of a session stuck at one row.
        let work = DispatchWorkItem { [weak self] in self?.openPendingSwitcher() }
        pendingSwitcherOpen = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func openPendingSwitcher() {
        guard let work = pendingSwitcherOpen else { return }
        work.cancel()
        pendingSwitcherOpen = nil
        // A swipe carried momentum, so it earns a little more bounce than a keypress.
        present(.switcher, animation: switcherTrigger == .gesture ? Motion.openFromSwipe : Motion.open)
    }

    /// Temporary input used only while the switcher is open, torn down the moment it closes.
    private func installSwitcherSessionInput(for trigger: SwitcherTrigger) {
        let hotKeys = HotKeyCenter.shared
        let modifierSets = [0, optionKey, optionKey | shiftKey]
        for modifiers in modifierSets {
            sessionHotKeys += [
                hotKeys.register(keyCode: kVK_Escape, modifiers: modifiers) { [weak self] in self?.switcher.cancel() },
                hotKeys.register(keyCode: kVK_UpArrow, modifiers: modifiers) { [weak self] in self?.switcher.step(-1) },
                hotKeys.register(keyCode: kVK_DownArrow, modifiers: modifiers) { [weak self] in self?.switcher.step(1) },
                hotKeys.register(keyCode: kVK_Return, modifiers: modifiers) { [weak self] in self?.switcher.commit() },
            ].compactMap { $0 }
        }

        if trigger == .keyboard {
            modifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard !event.modifierFlags.contains(.option) else { return }
                MainActor.assumeIsolated {
                    guard let self, self.switcherTrigger == .keyboard else { return }
                    self.switcher.commit()
                }
            }
        }
    }

    private func endSwitcherSession() {
        pendingSwitcherOpen?.cancel()
        pendingSwitcherOpen = nil
        sessionHotKeys.forEach(HotKeyCenter.shared.unregister)
        sessionHotKeys.removeAll()
        if let monitor = modifierMonitor { NSEvent.removeMonitor(monitor) }
        modifierMonitor = nil
        switcherTrigger = nil
    }

    private func finishSwitch(to window: WindowInfo) {
        dismiss()
        WindowFocuser.focus(window)
    }

    private func haptic() {
        guard Config.hapticFeedback else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    // MARK: - Clipboard

    func toggleClipboard() {
        if state.mode == .clipboard {
            dismiss()
            return
        }
        endSwitcherSession()
        clipboardTarget = NSWorkspace.shared.frontmostApplication
        clipboard.prepareForPresentation()
        present(.clipboard)
    }

    private func finishClipboard(with item: ClipItem, paste: Bool) {
        let target = clipboardTarget
        clipboard.copyToPasteboard(item)
        dismiss()
        guard paste, Permissions.hasAccessibility, let target, !target.isTerminated else { return }
        // Let the target app regain key focus before sending it ⌘V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            Paster.sendPasteShortcut()
        }
    }
}
