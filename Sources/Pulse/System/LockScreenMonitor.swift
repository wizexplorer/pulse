import Foundation

/// Reports the screen locking, and each unlock attempt while it's locked.
///
/// Locking and unlocking come from loginwindow's public distributed notifications, which cost
/// nothing while waiting. Whether an attempt *failed* has no public signal at all, so while (and
/// only while) the screen is locked, this follows loginwindow's own log, which records every
/// authentication result: "-[LWDefaultScreenLockUI authSuccess] | enter. password is CORRECT" and
/// "-[LWDefaultScreenLockUI authFailWithMessage:] | enter. INCORRECT password" (the latter for a wrong
/// password and for an unrecognized finger alike; verified on macOS 15.5).
/// That also reports a success ~50 ms before the public "unlocked" notification, so the lock opens
/// sooner. If the log can't be read, the public notification still opens the lock; only the
/// failure shake is lost.
///
/// Cost: one `log stream` process, blocked on a pipe, for as long as the screen is locked. The
/// filtering happens inside logd against a narrow predicate, so our process wakes only for the
/// handful of lines an unlock attempt produces. It's stopped the moment the screen unlocks.
@MainActor
final class LockScreenMonitor {
    enum Event {
        case locked
        case authenticationFailed
        /// Sent once per lock, before `unlocked`.
        case authenticationSucceeded
        case unlocked
    }

    var onEvent: ((Event) -> Void)?
    private(set) var isLocked = false

    private var observers: [NSObjectProtocol] = []
    private var logStream: Process?
    private var pending = Data()
    private var succeeded = false
    private var lastFailure = Date.distantPast

    /// The two messages that end an unlock attempt. Deliberately narrow: logd only wakes us for these.
    private static let successMessage = "-[LWDefaultScreenLockUI authSuccess] | enter"
    private static let failureMessage = "-[LWDefaultScreenLockUI authFailWithMessage:] | enter"
    private static let predicate = """
        process == "loginwindow" AND \
        (eventMessage BEGINSWITH "\(successMessage)" OR eventMessage BEGINSWITH "\(failureMessage)")
        """

    func start() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        observers = [
            center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.didLock() }
            },
            center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.didUnlock() }
            },
        ]
    }

    private func didLock() {
        guard !isLocked else { return }
        isLocked = true
        succeeded = false
        startLogStream()
        onEvent?(.locked)
    }

    private func didUnlock() {
        guard isLocked else { return }
        isLocked = false
        stopLogStream()
        reportSuccess()
        onEvent?(.unlocked)
    }

    private func reportSuccess() {
        guard !succeeded else { return }
        succeeded = true
        onEvent?(.authenticationSucceeded)
    }

    private func reportFailure() {
        // One attempt logs several lines; count it once.
        guard !succeeded, Date().timeIntervalSince(lastFailure) > 0.4 else { return }
        lastFailure = Date()
        onEvent?(.authenticationFailed)
    }

    // MARK: - loginwindow's log

    private func startLogStream() {
        guard logStream == nil else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--style", "compact", "--predicate", Self.predicate]
        process.qualityOfService = .utility
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.consume(data) } }
        }
        do {
            try process.run()
            logStream = process
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            Log.app.error("lock screen: can't follow loginwindow's log: \(error.localizedDescription)")
        }
    }

    private func stopLogStream() {
        guard let process = logStream else { return }
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        logStream = nil
        pending.removeAll()
    }

    private func consume(_ data: Data) {
        pending.append(data)
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let line = String(decoding: pending[pending.startIndex..<newline], as: UTF8.self)
            pending.removeSubrange(pending.startIndex...newline)
            classify(line)
        }
    }

    private func classify(_ line: String) {
        // Only real entries count. `log stream` first prints a "Filtering the log data using …" header
        // that repeats the predicate, message names included: read as an entry, it faked an unlock
        // the moment the screen locked.
        guard isLocked, line.contains(" loginwindow[") else { return }
        if line.contains(Self.successMessage) {
            reportSuccess()
        } else if line.contains(Self.failureMessage) {
            reportFailure()
        }
    }
}
