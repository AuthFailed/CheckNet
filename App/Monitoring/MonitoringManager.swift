import Foundation
import Observation
import NetworkKit

/// A small in-pocket uptime monitor: periodically pings a list of hosts and
/// posts local notifications when a host goes down or recovers. Runs a live
/// loop while the app is active; hands off to `BackgroundMonitor` for the same
/// checks while suspended.
@MainActor
@Observable
final class MonitoringManager {
    private(set) var entries: [MonitoredEntry] = []
    var isMonitoring = false
    var intervalSeconds: Double = 60
    var notificationsAuthorized = false

    private var loopTask: Task<Void, Never>?

    init() {
        entries = MonitorStore.load()
    }

    // MARK: Host list

    func add(_ host: String) {
        let h = host.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty, !entries.contains(where: { $0.host == h }) else { return }
        entries.append(MonitoredEntry(host: h))
        persist()
        Task { await checkOne(index: entries.count - 1) }
    }

    func remove(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        persist()
    }

    // MARK: Monitoring loop

    func toggleMonitoring() {
        isMonitoring ? stop() : start()
    }

    func start() {
        guard !isMonitoring, !entries.isEmpty else { return }
        isMonitoring = true
        Task { await requestNotificationAuthorization() }
        // Keep watching once the app is backgrounded, too.
        #if os(iOS)
        BackgroundMonitor.schedule()
        #endif
        loopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await checkAll()
                try? await Task.sleep(for: .seconds(max(10, intervalSeconds)))
            }
        }
    }

    func stop() {
        isMonitoring = false
        loopTask?.cancel()
        loopTask = nil
        #if os(iOS)
        BackgroundMonitor.cancel()
        #endif
    }

    func checkAll() async {
        for index in entries.indices {
            if Task.isCancelled { break }
            await checkOne(index: index)
        }
    }

    private func checkOne(index: Int) async {
        guard entries.indices.contains(index) else { return }
        let host = entries[index].host
        let previous = entries[index].status

        let stats = try? await ICMPPinger().measure(host: host, config: .quick)
        let loss = stats?.lossPercent ?? 100
        let latency = stats?.avg
        let newStatus = PingSnapshot.status(loss: loss, latency: latency)

        guard entries.indices.contains(index), entries[index].host == host else { return }
        entries[index].status = newStatus
        entries[index].lastLatency = latency
        entries[index].lastChecked = Date()
        entries[index].lossPercent = loss
        persist()

        SharedStore.saveSnapshot(PingSnapshot(
            host: host, ip: stats?.resolvedIP ?? host, latencyMillis: latency,
            lossPercent: loss, jitterMillis: stats?.jitter, status: newStatus, timestamp: Date()
        ))

        if let transition = MonitorNotification.transition(from: previous, to: newStatus) {
            HostNotifier.post(MonitorNotification.plan(host: host, transition: transition), host: host)
        }
    }

    // MARK: Notifications

    func requestNotificationAuthorization() async {
        notificationsAuthorized = await HostNotifier.shared.requestAuthorization()
    }

    // MARK: Persistence

    private func persist() {
        MonitorStore.save(entries)
        SharedStore.setMonitoredHosts(entries.map(\.host))
    }
}
