import Foundation
#if canImport(ActivityKit) && !os(macOS)
import ActivityKit

/// Manages one Live Activity (Lock Screen + Dynamic Island) for a check —
/// ping, monitoring, or any other tool with a long-running, glanceable state.
///
/// Deliberately *not* `@MainActor`: `ActivityKit.Activity` is non-Sendable and
/// its `update`/`end` are `nonisolated async`, so the activity is owned outside
/// the main actor to avoid cross-domain sends. A single owner drives it
/// sequentially, so a lock covers the rare concurrent access.
final class CheckActivityController: @unchecked Sendable {
    private let lock = NSLock()
    private var activity: Activity<CheckActivityAttributes>?

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(kind: CheckActivityKind, title: String, subtitle: String, view: CheckActivityView) {
        guard isSupported else { return }
        let existing = lock.withLock { activity }
        guard existing == nil else { return }

        let attributes = CheckActivityAttributes(kind: kind, title: title, subtitle: subtitle)
        let started = try? Activity.request(
            attributes: attributes,
            content: .init(state: .init(view), staleDate: nil))
        lock.withLock { activity = started }
    }

    func update(_ view: CheckActivityView) async {
        let current = lock.withLock { activity }
        guard let current else { return }
        await current.update(.init(state: .init(view), staleDate: nil))
    }

    func end(_ view: CheckActivityView) async {
        let current = lock.withLock { () -> Activity<CheckActivityAttributes>? in
            let a = activity; activity = nil; return a
        }
        guard let current else { return }
        await current.end(.init(state: .init(view), staleDate: nil), dismissalPolicy: .after(.now + 4))
    }

    /// Ends any lingering activities of a kind — e.g. a monitoring activity left
    /// over from a previous launch, since monitoring is off on a cold start.
    static func endStale(kind: CheckActivityKind) {
        Task {
            for activity in Activity<CheckActivityAttributes>.activities where activity.attributes.kind == kind {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
#else

/// macOS has no Live Activities. The stub keeps the call sites free of platform
/// conditionals; every entry point is a no-op and `isSupported` is `false`.
final class CheckActivityController: @unchecked Sendable {
    var isSupported: Bool { false }
    func start(kind: CheckActivityKind, title: String, subtitle: String, view: CheckActivityView) {}
    func update(_ view: CheckActivityView) async {}
    func end(_ view: CheckActivityView) async {}
    static func endStale(kind: CheckActivityKind) {}
}
#endif
