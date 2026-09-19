import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var island: IslandController!
    private var clipboardMonitor: ClipboardMonitor!
    private var gestures: TrackpadGestureMonitor?
    private var keyboardFallback: KeyboardTap?
    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?
    private var accessibilityObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = ClipboardStore(maxItems: Config.clipboardHistoryLimit)
        let clipboardModel = ClipboardModel(store: store)
        island = IslandController(clipboard: clipboardModel)
        island.onPresent = { [weak self] in self?.startAccessibilityFeaturesIfPossible() }
        clipboardMonitor = ClipboardMonitor(store: store, model: clipboardModel)
        clipboardMonitor.start()
        AppActivationTracker.shared.start()

        registerHotKeys()
        installDevHooksIfRequested()
        LaunchAtLogin.enableOnFirstInstalledLaunch()
        installStatusItem()

        Log.app.info("launched; accessibility: \(Permissions.hasAccessibility)")
        if Permissions.hasAccessibility {
            startAccessibilityFeaturesIfPossible()
        } else {
            Permissions.requestAccessibility()
        }
        // Event driven (no polling): fires whenever the Accessibility allow-list changes.
        accessibilityObserver = Permissions.observeAccessibilityChanges { [weak self] in
            self?.startAccessibilityFeaturesIfPossible()
        }
    }

    // MARK: - Input

    private func registerHotKeys() {
        let hotKeys = HotKeyCenter.shared
        let forward = hotKeys.register(keyCode: kVK_Tab, modifiers: optionKey) { [weak self] in
            self?.island.switcherHotKey(reverse: false)
        }
        hotKeys.register(keyCode: kVK_Tab, modifiers: optionKey | shiftKey) { [weak self] in
            self?.island.switcherHotKey(reverse: true)
        }
        hotKeys.register(keyCode: Config.clipboardHotKey.keyCode, modifiers: Config.clipboardHotKey.modifiers) { [weak self] in
            self?.island.toggleClipboard()
        }
        // macOS 15.0 briefly refused Option-only hotkeys. If that ever comes back, fall back to a
        // narrowly-scoped keyboard event tap (created only in that case, so it normally costs nothing).
        if forward == nil {
            let tap = KeyboardTap()
            tap.onOptionTab = { [weak self] reverse in self?.island.switcherHotKey(reverse: reverse) }
            keyboardFallback = tap
        }
    }

    private func startAccessibilityFeaturesIfPossible() {
        guard Permissions.hasAccessibility else { return }
        keyboardFallback?.start()
        guard Config.trackpadGesturesEnabled, gestures == nil else { return }
        let monitor = TrackpadGestureMonitor()
        monitor.onBegin = { [weak self] direction in self?.island.switcherGestureBegan(direction) }
        monitor.onStep = { [weak self] direction in self?.island.switcherGestureStepped(direction) }
        monitor.onEnd = { [weak self] in self?.island.switcherGestureEnded() }
        let started = monitor.start()
        Log.input.info("trackpad gesture monitor started: \(started)")
        if started { gestures = monitor }
    }

    // MARK: - Development

    /// Lets tooling drive the island without a keyboard, for recording and measuring animations:
    ///   open --env PULSE_DEV_HOOKS=1 build/Pulse.app
    ///   swift scripts/island.swift switcher|clipboard|dismiss
    /// Off unless the app is launched with that variable, so normal use registers nothing.
    private var devHookObserver: NSObjectProtocol?

    private func installDevHooksIfRequested() {
        guard ProcessInfo.processInfo.environment["PULSE_DEV_HOOKS"] != nil else { return }
        devHookObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("dev.pulse.Pulse.command"), object: nil, queue: .main
        ) { [weak self] note in
            let command = note.object as? String
            MainActor.assumeIsolated {
                guard let island = self?.island else { return }
                switch command {
                case "switcher": island.showSwitcher()
                case "clipboard": island.toggleClipboard()
                case "dismiss": island.dismiss()
                default: break
                }
            }
        }
    }

    // MARK: - Menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusIcon.make()
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "", action: #selector(openAccessibility), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Clipboard History  ⌃⌘V", action: #selector(showClipboard), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Window Switcher  ⌥⇥", action: #selector(showSwitcher), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Clear Clipboard History", action: #selector(clearHistory), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let loginItem = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        launchAtLoginItem = loginItem
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Pulse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let granted = Permissions.hasAccessibility
        if granted { startAccessibilityFeaturesIfPossible() }
        launchAtLoginItem?.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.items.first?.title = granted
            ? "Accessibility: allowed ✓"
            : "Accessibility: not allowed. Open Settings…"
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
    }

    @objc private func showClipboard() { island.toggleClipboard() }
    @objc private func showSwitcher() { island.showSwitcher() }
    @objc private func openAccessibility() { Permissions.openAccessibilitySettings() }
    @objc private func clearHistory() { island.clipboard.clearAll() }
}
