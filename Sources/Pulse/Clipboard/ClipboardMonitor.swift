import AppKit

/// Watches the general pasteboard for new content.
///
/// macOS offers no change notification, so we check `changeCount` (one cheap IPC, no data copied) on
/// a timer with generous leeway so the kernel can batch the wakeup with others. On top of that:
/// - an extra check whenever the frontmost app changes (copy → switch app → paste is the common flow),
/// - the timer is torn down entirely while the displays sleep, the Mac sleeps, or the user session
///   is switched away, so an idle Mac gets zero wakeups from us.
@MainActor
final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private let store: ClipboardStore
    private weak var model: ClipboardModel?
    private var lastChangeCount: Int
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []

    init(store: ClipboardStore, model: ClipboardModel) {
        self.store = store
        self.model = model
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        resume()
        let center = NSWorkspace.shared.notificationCenter
        let pauses: [Notification.Name] = [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.willSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ]
        let resumes: [Notification.Name] = [
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        for name in pauses {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pause() }
            })
        }
        for name in resumes {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume() }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        })
    }

    private func resume() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Config.clipboardPollInterval, repeating: Config.clipboardPollInterval, leeway: Config.clipboardPollLeeway)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.resume()
        self.timer = timer
        check()
    }

    private func pause() {
        timer?.cancel()
        timer = nil
    }

    func check() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let source, Config.ignoredSourceBundleIDs.contains(source) { return }
        guard let capture = ClipCapture.read(from: pasteboard) else { return }

        store.record(capture, sourceBundleID: source) { [weak model] item, pruned in
            model?.didRecord(item, pruned: pruned)
        }
    }
}
