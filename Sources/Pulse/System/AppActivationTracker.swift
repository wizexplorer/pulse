import AppKit

/// Remembers the order apps were last activated in, from workspace notifications (no polling).
/// Used to order windows that aren't on screen (minimized, hidden apps) in the switcher.
@MainActor
final class AppActivationTracker {
    static let shared = AppActivationTracker()

    private var recency: [pid_t] = []
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        if let front = NSWorkspace.shared.frontmostApplication { recency = [front.processIdentifier] }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated {
                let tracker = AppActivationTracker.shared
                tracker.recency.removeAll { $0 == pid }
                tracker.recency.insert(pid, at: 0)
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { AppActivationTracker.shared.recency.removeAll { $0 == pid } }
        })
    }

    /// Lower is more recent. Apps never activated since launch sort last.
    func rank(of pid: pid_t) -> Int {
        recency.firstIndex(of: pid) ?? Int.max
    }
}
