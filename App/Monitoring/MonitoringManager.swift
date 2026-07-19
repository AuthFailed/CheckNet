import Foundation
import Observation
import UserNotifications
import NetworkKit

/// A monitored host and its latest observed state.
struct MonitoredEntry: Identifiable, Codable, Hashable {
    var id: String { host }
    var host: String
    var status: PingSnapshot.Status = .unknown
    var lastLatency: Double?
    var lastChecked: Date?
    var lossPercent: Double = 0
}

/// A small in-pocket uptime monitor: periodically pings a list of hosts while
/// active and posts local notifications when a host goes down or recovers.
@MainActor
@Observable
final class MonitoringManager {
    private(set) var entries: [MonitoredEntry] = []
    var isMonitoring = false
    var intervalSeconds: Double = 60
    var notificationsAuthorized = false

    private var loopTask: Task<Void, Never>?
    private let stateKey = "checknet.monitorEntries"

    init() {
        load()
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

        let stats = try? await ICMPPinger().measure(host: host, config: PingConfig(count: 3, interval: 0.3, timeout: 2))
        let received = stats?.received ?? 0
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

        notifyIfTransition(host: host, from: previous, to: newStatus, received: received)
    }

    // MARK: Notifications

    private func notifyIfTransition(host: String, from: PingSnapshot.Status, to: PingSnapshot.Status, received: Int) {
        guard from != .unknown, from != to else { return }
        let wentDown = (to == .down) && (from == .ok || from == .degraded)
        let recovered = (to == .ok || to == .degraded) && from == .down
        guard wentDown || recovered else { return }
        postNotification(
            title: wentDown ? "❌ \(host) недоступен" : "✅ \(host) снова онлайн",
            body: wentDown ? "Хост перестал отвечать на ping." : "Хост восстановил соединение."
        )
    }

    func requestNotificationAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        notificationsAuthorized = granted
    }

    private func postNotification(title: String, body: String) {
        guard notificationsAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            AppGroup.defaults.set(data, forKey: stateKey)
        }
        SharedStore.setMonitoredHosts(entries.map(\.host))
    }

    private func load() {
        if let data = AppGroup.defaults.data(forKey: stateKey),
           let decoded = try? JSONDecoder().decode([MonitoredEntry].self, from: data) {
            entries = decoded
        }
    }
}
