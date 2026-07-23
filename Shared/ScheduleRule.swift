import Foundation

/// The pure "is this recurring task due?" rule, split out so its interval and
/// clamping behaviour can be unit-tested without the `@Observable` store.
enum ScheduleRule {
    static let minimumIntervalMinutes = 5

    /// Whether a task should run at `now`, given whether it's enabled, when it
    /// last ran, and its interval. A never-run enabled task is always due; the
    /// interval is clamped up to `minimumIntervalMinutes`.
    static func isDue(isEnabled: Bool, lastRun: Date?, intervalMinutes: Int, now: Date,
                      minimumIntervalMinutes: Int = minimumIntervalMinutes) -> Bool {
        guard isEnabled else { return false }
        guard let last = lastRun else { return true }
        let interval = TimeInterval(max(minimumIntervalMinutes, intervalMinutes) * 60)
        return now.timeIntervalSince(last) >= interval
    }
}
