import Foundation

/// Cross-cut signal from the ping Live Activity's "Stop" button to the running
/// ping loop. A monotonically increasing generation rather than a bare bool, so
/// the loop can tell "stop pressed *since I started*" from a stale flag left by
/// a previous run — snapshot the generation at start, then watch for it to grow.
///
/// Pure storage in `Shared/` so both the intent (which bumps it) and the view
/// model (which watches it) share one key, and the semantics are unit-tested.
enum LiveActivitySignal {
    static let key = "checknet.ping.stopGeneration"

    static func generation(_ defaults: UserDefaults = AppGroup.defaults) -> Int {
        defaults.integer(forKey: key)
    }

    /// Pressed by the Live Activity button.
    static func requestStop(_ defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(generation(defaults) + 1, forKey: key)
    }

    /// True once a stop was requested after `baseline`.
    static func stopRequested(since baseline: Int, _ defaults: UserDefaults = AppGroup.defaults) -> Bool {
        generation(defaults) > baseline
    }
}

/// Persisted config written by the Monitoring Focus filter and read by the
/// notifier in both the foreground and the background process. Pure storage so
/// the gate is testable without an active Focus.
enum FocusMonitorState {
    static let key = "checknet.focus.muteHostAlerts"

    static func setMuted(_ muted: Bool, _ defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(muted, forKey: key)
    }

    static func isMuted(_ defaults: UserDefaults = AppGroup.defaults) -> Bool {
        defaults.bool(forKey: key)
    }
}
