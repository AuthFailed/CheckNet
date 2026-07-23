import Foundation

/// The pure decision layer behind uptime notifications: what counts as a
/// state change worth telling the user about, and exactly what that
/// notification should say. Kept UI- and UserNotifications-free so the
/// transition matrix and copy are unit-tested rather than eyeballed on a device.
enum MonitorNotification {
    /// Category and action identifiers, single-sourced so the app's category
    /// registration and its delegate agree.
    static let categoryID = "HOST_STATUS"
    static let actionOpen = "OPEN_HOST"
    static let actionRecheck = "RECHECK_HOST"
    static let hostKey = "host"

    enum Transition: Equatable { case down, recovered }

    /// A notifiable transition, or nil. A first observation (`from == .unknown`)
    /// never alerts — we only report a *change* from a known state, and flapping
    /// within the "up" band (ok ↔ degraded) is not worth a push.
    static func transition(from: PingSnapshot.Status, to: PingSnapshot.Status) -> Transition? {
        guard from != .unknown, from != to else { return nil }
        if to == .down, from == .ok || from == .degraded { return .down }
        if from == .down, to == .ok || to == .degraded { return .recovered }
        return nil
    }

    /// What the system notification should contain for a transition.
    struct Plan: Equatable {
        var title: String
        var body: String
        /// Down alerts ask for time-sensitive delivery so they break through
        /// Focus; recoveries are ordinary. The level degrades gracefully to
        /// `.active` on builds without the time-sensitive entitlement.
        var timeSensitive: Bool
        /// Groups a host's alerts into one thread in Notification Center.
        var threadID: String
    }

    static func plan(host: String, transition: Transition) -> Plan {
        switch transition {
        case .down:
            return Plan(title: "❌ \(host) недоступен",
                        body: "Хост перестал отвечать на ping.",
                        timeSensitive: true, threadID: host)
        case .recovered:
            return Plan(title: "✅ \(host) снова онлайн",
                        body: "Хост восстановил соединение.",
                        timeSensitive: false, threadID: host)
        }
    }
}

/// Pure scheduling helper for the background refresh cadence.
enum BackgroundRefresh {
    /// The system enforces a floor of roughly 15 minutes on app-refresh tasks,
    /// so asking for less just wastes the request.
    static let minimumMinutes = 15

    static func earliestBeginDate(now: Date, intervalMinutes: Int,
                                  minimumMinutes: Int = minimumMinutes) -> Date {
        now.addingTimeInterval(TimeInterval(max(minimumMinutes, intervalMinutes) * 60))
    }
}
