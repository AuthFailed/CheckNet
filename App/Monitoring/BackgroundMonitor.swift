#if os(iOS)
import Foundation
import BackgroundTasks
import NetworkKit

/// Runs the uptime checks while the app is suspended, via `BGTaskScheduler`.
///
/// A suspended app gets no CPU, so foreground-only monitoring stops the moment
/// the app leaves the screen. An app-refresh task lets the system wake us
/// periodically — on its own budget, it decides exactly when — to re-check the
/// monitored hosts and fire a notification if one changed state. The identifier
/// is declared in `BGTaskSchedulerPermittedIdentifiers`; `UIBackgroundModes`
/// carries `fetch`.
enum BackgroundMonitor {
    static let taskID = "com.chrsnv.checknet.monitor.refresh"

    /// Requested cadence; the system enforces its own, longer, floor.
    static let intervalMinutes = BackgroundRefresh.minimumMinutes

    /// Registers the launch handler. Must run before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            handle(refresh)
        }
    }

    /// Asks the system to wake us again later — only if there is something to watch.
    static func schedule() {
        guard !MonitorStore.load().isEmpty else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = BackgroundRefresh.earliestBeginDate(
            now: Date(), intervalMinutes: intervalMinutes)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Drops any pending refresh (the user turned monitoring off).
    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
    }

    /// The BG task is not `Sendable`; box it so the completion can cross into
    /// the work `Task` without tripping Swift 6's data-race check. Completing it
    /// from the task's executor is fine — `setTaskCompleted` is thread-safe.
    private struct UncheckedBox<T>: @unchecked Sendable {
        let value: T
        init(_ value: T) { self.value = value }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()   // chain the next wake-up first, in case this pass is killed
        let box = UncheckedBox(task)
        let work = Task {
            await runPass()
            box.value.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// One check pass over every monitored host, posting on any state change.
    /// Also used by the "Проверить снова" notification action.
    static func runPass() async {
        var entries = MonitorStore.load()
        guard !entries.isEmpty else { return }
        for index in entries.indices {
            if Task.isCancelled { break }
            let host = entries[index].host
            let previous = entries[index].status

            let stats = try? await ICMPPinger().measure(host: host, config: .quick)
            let loss = stats?.lossPercent ?? 100
            let latency = stats?.avg
            let status = PingSnapshot.status(loss: loss, latency: latency)

            entries[index].status = status
            entries[index].lastLatency = latency
            entries[index].lastChecked = Date()
            entries[index].lossPercent = loss

            SharedStore.saveSnapshot(PingSnapshot(
                host: host, ip: stats?.resolvedIP ?? host, latencyMillis: latency,
                lossPercent: loss, jitterMillis: stats?.jitter, status: status, timestamp: Date()))

            if let transition = MonitorNotification.transition(from: previous, to: status) {
                HostNotifier.post(MonitorNotification.plan(host: host, transition: transition), host: host)
            }
        }
        MonitorStore.save(entries)
    }
}
#endif
