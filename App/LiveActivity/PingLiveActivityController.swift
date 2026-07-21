import Foundation
#if canImport(ActivityKit) && !os(macOS)
import ActivityKit

/// Manages the ping Live Activity (Lock Screen + Dynamic Island) for a run.
///
/// Deliberately *not* `@MainActor`: `ActivityKit.Activity` is non-Sendable and
/// its `update`/`end` methods are `nonisolated async`, so the activity must be
/// owned outside the main actor to avoid cross-domain sends. A run is driven
/// sequentially, so a lock is sufficient for the rare concurrent access.
final class PingLiveActivityController: @unchecked Sendable {
    private let lock = NSLock()
    private var activity: Activity<PingActivityAttributes>?

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(host: String, ip: String) {
        guard isSupported else { return }
        let existing = lock.withLock { activity }
        guard existing == nil else { return }

        let attributes = PingActivityAttributes(host: host, ip: ip)
        let initial = PingActivityAttributes.ContentState(
            latencyMillis: nil, lossPercent: 0, received: 0, transmitted: 0,
            status: .unknown, isRunning: true
        )
        let started = try? Activity.request(attributes: attributes, content: .init(state: initial, staleDate: nil))
        lock.withLock { activity = started }
    }

    func update(latency: Double?, loss: Double, received: Int, transmitted: Int, status: PingSnapshot.Status) async {
        let current = lock.withLock { activity }
        guard let current else { return }
        let state = PingActivityAttributes.ContentState(
            latencyMillis: latency, lossPercent: loss, received: received,
            transmitted: transmitted, status: status, isRunning: true
        )
        await current.update(.init(state: state, staleDate: nil))
    }

    func end(latency: Double?, loss: Double, received: Int, transmitted: Int, status: PingSnapshot.Status) async {
        let current = lock.withLock { () -> Activity<PingActivityAttributes>? in
            let a = activity; activity = nil; return a
        }
        guard let current else { return }
        let state = PingActivityAttributes.ContentState(
            latencyMillis: latency, lossPercent: loss, received: received,
            transmitted: transmitted, status: status, isRunning: false
        )
        await current.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now + 4))
    }
}
#else

/// macOS has no Live Activities. The stub keeps the call sites in
/// `PingViewModel` free of platform conditionals; every entry point is a no-op
/// and `isSupported` is always `false`.
final class PingLiveActivityController: @unchecked Sendable {
    var isSupported: Bool { false }

    func start(host: String, ip: String) {}

    func update(latency: Double?, loss: Double, received: Int, transmitted: Int, status: PingSnapshot.Status) async {}

    func end(latency: Double?, loss: Double, received: Int, transmitted: Int, status: PingSnapshot.Status) async {}
}
#endif
