import Foundation
import Observation
import NetworkKit

/// A recurring run of a set of blocking checks whose results are sent as
/// webhooks.
///
/// **Platform reality:** iOS does not let an app run reliably on a timer in the
/// background — a suspended app gets no CPU. So this scheduler runs only while
/// the app is in the foreground. For unattended, guaranteed periodicity the app
/// points the user at a Shortcuts personal automation (which can fire on a
/// schedule and call the CheckNet intents); that path is spelled out in the UI.
struct WebhookSchedule: Codable, Equatable {
    var isEnabled: Bool = false
    /// How often to run, in minutes. Clamped to a sane floor when scheduling.
    var intervalMinutes: Int = 30
    /// Raw values of the blocking checks to run each tick.
    var checkIDs: [String] = []
    /// Optional shared target; empty means each check uses its own default.
    var target: String = ""

    static let minimumIntervalMinutes = 5
}

/// Drives the schedule while the app is active.
@MainActor
@Observable
final class WebhookScheduler {
    private(set) var schedule: WebhookSchedule {
        didSet { persist() }
    }
    private(set) var lastRun: Date?
    private(set) var lastSummary: String?
    private(set) var isRunning = false

    private var loop: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    private let key = "checknet.webhook.schedule"

    init() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(WebhookSchedule.self, from: data) {
            schedule = decoded
        } else {
            schedule = WebhookSchedule()
        }
    }

    func update(_ newValue: WebhookSchedule) {
        schedule = newValue
        restart()
    }

    /// Starts the foreground loop if the schedule is enabled and has work.
    func startIfNeeded() {
        guard schedule.isEnabled, !schedule.checkIDs.isEmpty, loop == nil else { return }
        let interval = max(WebhookSchedule.minimumIntervalMinutes, schedule.intervalMinutes)
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(Double(interval) * 60))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    private func restart() {
        stop()
        startIfNeeded()
    }

    private func tick() async {
        guard !isRunning else { return }
        isRunning = true
        var restricted = 0
        for id in schedule.checkIDs {
            guard let check = BlockingCheck(rawValue: id) else { continue }
            let target = schedule.target.isEmpty ? check.defaultTarget : schedule.target
            let finding = await check.run(target: target)
            if finding.verdict == .restricted { restricted += 1 }
            WebhookReporter.reportBlocking(check: id, target: target, finding: finding, eventPrefix: "schedule")
            SharedStore.appendHistory(CheckRecord(
                tool: "blocking.\(id)", host: target, timestamp: Date(),
                latencyMillis: nil, lossPercent: nil,
                succeeded: finding.verdict != .restricted,
                detail: finding.headline, source: .scheduled
            ))
        }
        lastRun = Date()
        lastSummary = restricted == 0
            ? "Ограничений не найдено (\(schedule.checkIDs.count))."
            : "Найдено ограничений: \(restricted) из \(schedule.checkIDs.count)."
        isRunning = false
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(schedule) {
            defaults.set(data, forKey: key)
        }
    }
}
