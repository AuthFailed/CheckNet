import Foundation
import Observation
import NetworkKit

/// A recurring test the app runs on an interval.
///
/// Scheduling is independent of webhooks: a task always records to the scheduled
/// history, and additionally sends a webhook when webhooks are configured. Tasks
/// are created from a test's own screen (its host/target baked in) and also
/// listed centrally under automation.
struct ScheduledTask: Identifiable, Codable, Hashable {
    /// What to run each tick.
    enum Kind: Codable, Hashable {
        case ping(host: String)
        case blocking(checkID: String, target: String)

        var toolLabel: String {
            switch self {
            case .ping: "Ping"
            case .blocking(let id, _): BlockingCheck(rawValue: id)?.title ?? "Блокировка"
            }
        }

        var target: String {
            switch self {
            case .ping(let host): host
            case .blocking(_, let target): target
            }
        }
    }

    var id: UUID = UUID()
    var kind: Kind
    var intervalMinutes: Int = 30
    var isEnabled: Bool = true
    var lastRun: Date?
    var lastSummary: String?

    static let minimumIntervalMinutes = ScheduleRule.minimumIntervalMinutes

    /// Whether the task is due to run at `now`, given its interval and last run.
    func isDue(at now: Date) -> Bool {
        ScheduleRule.isDue(isEnabled: isEnabled, lastRun: lastRun,
                           intervalMinutes: intervalMinutes, now: now)
    }

    var title: String { "\(kind.toolLabel) · \(kind.target)" }
}

/// Persists scheduled tasks.
@MainActor
@Observable
final class ScheduledTaskStore {
    private(set) var tasks: [ScheduledTask] {
        didSet { persist() }
    }
    private let defaults = UserDefaults.standard
    private let key = "checknet.scheduledTasks"

    init() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ScheduledTask].self, from: data) {
            tasks = decoded
        } else {
            tasks = []
        }
    }

    func add(_ task: ScheduledTask) {
        tasks.append(task)
    }

    func update(_ task: ScheduledTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
    }

    func remove(_ task: ScheduledTask) {
        tasks.removeAll { $0.id == task.id }
    }

    /// Tasks scheduled for a given ping host (to show state in the ping card).
    func pingTasks(host: String) -> [ScheduledTask] {
        tasks.filter {
            if case .ping(let h) = $0.kind { return h.caseInsensitiveCompare(host) == .orderedSame }
            return false
        }
    }

    fileprivate func markRun(_ id: UUID, at date: Date, summary: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].lastRun = date
        tasks[index].lastSummary = summary
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(tasks) {
            defaults.set(data, forKey: key)
        }
    }
}

/// Runs due tasks while the app is in the foreground.
///
/// iOS gives a suspended app no CPU, so — like the rest of the app's automation
/// — this only ticks while active. For guaranteed background periodicity the UI
/// points the user at a Shortcuts personal automation calling the intents.
@MainActor
@Observable
final class TaskScheduler {
    private let store: ScheduledTaskStore
    private var loop: Task<Void, Never>?

    init(store: ScheduledTaskStore) {
        self.store = store
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tickDueTasks()
                // Check every 30 s; each task's own interval gates whether it runs.
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    private func tickDueTasks() async {
        let now = Date()
        let due = store.tasks.filter { $0.isDue(at: now) }
        for task in due {
            await run(task)
        }
    }

    /// Runs one task now (used by the tick loop and by a manual "run now").
    func run(_ task: ScheduledTask) async {
        let summary: String
        switch task.kind {
        case .ping(let host):
            summary = await runPing(host: host)
        case .blocking(let checkID, let target):
            summary = await runBlocking(checkID: checkID, target: target)
        }
        store.markRun(task.id, at: Date(), summary: summary)
    }

    private func runPing(host: String) async -> String {
        let config = PingConfig(count: 5, interval: 0.3, timeout: 2)
        do {
            let stats = try await ICMPPinger().measure(host: host, config: config)
            SharedStore.appendHistory(CheckRecord(
                tool: "ping", host: host, timestamp: Date(),
                latencyMillis: stats.avg, lossPercent: stats.lossPercent,
                succeeded: stats.received > 0,
                detail: "\(stats.received)/\(stats.transmitted), \(Int(stats.lossPercent))% потерь",
                source: .scheduled
            ))
            WebhookReporter.reportPing(stats, samples: [])
            return stats.received > 0
                ? "\(Int(stats.avg ?? 0)) мс, потери \(Int(stats.lossPercent))%"
                : "хост недоступен"
        } catch {
            SharedStore.appendHistory(CheckRecord(
                tool: "ping", host: host, timestamp: Date(),
                latencyMillis: nil, lossPercent: nil, succeeded: false,
                detail: "ошибка: \(error.localizedDescription)", source: .scheduled
            ))
            return "ошибка"
        }
    }

    private func runBlocking(checkID: String, target: String) async -> String {
        guard let kind = CensorshipCheckKind(rawValue: checkID) else { return "неизвестная проверка" }
        let host = target.isEmpty ? kind.defaultTarget : target
        let finding = await kind.run(target: host)
        SharedStore.appendHistory(CheckRecord(
            tool: "blocking.\(checkID)", host: host, timestamp: Date(),
            latencyMillis: nil, lossPercent: nil,
            succeeded: finding.verdict != .restricted,
            detail: finding.headline, source: .scheduled
        ))
        WebhookReporter.reportBlocking(check: checkID, target: host, finding: finding, eventPrefix: "schedule")
        return finding.headline
    }
}
