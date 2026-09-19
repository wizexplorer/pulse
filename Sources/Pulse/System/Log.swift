import os

/// View with: log stream --predicate 'subsystem == "dev.pulse.Pulse"' --level info
enum Log {
    static let app = Logger(subsystem: "dev.pulse.Pulse", category: "app")
    static let switcher = Logger(subsystem: "dev.pulse.Pulse", category: "switcher")
    static let input = Logger(subsystem: "dev.pulse.Pulse", category: "input")
}
