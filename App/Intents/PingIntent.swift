import AppIntents
import NetworkKit

/// Runs a quick ping to a host. Exposed to Siri, Shortcuts and automations
/// (e.g. "when I get home → test the router").
struct PingHostIntent: AppIntent {
    static let title: LocalizedStringResource = "Проверить хост"
    static let description = IntentDescription("Пингует хост и сообщает задержку и потери.")
    static let openAppWhenRun = false

    @Parameter(title: "Хост или IP", requestValueDialog: "Какой хост проверить?")
    var host: String

    @Parameter(title: "Число пакетов", default: 5)
    var count: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Проверить \(\.$host)") {
            \.$count
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        let config = PingConfig(count: max(1, min(count, 50)), interval: 0.3, timeout: 2.0)
        let stats = try await ICMPPinger().measure(host: host, config: config)

        let snapshot = PingSnapshot(
            host: host,
            ip: stats.resolvedIP,
            latencyMillis: stats.avg,
            lossPercent: stats.lossPercent,
            jitterMillis: stats.jitter,
            status: PingSnapshot.status(loss: stats.lossPercent, latency: stats.avg),
            timestamp: Date()
        )
        SharedStore.saveSnapshot(snapshot)
        SharedStore.appendHistory(CheckRecord(
            tool: "ping", host: host, timestamp: Date(),
            latencyMillis: stats.avg, lossPercent: stats.lossPercent,
            succeeded: stats.received > 0,
            detail: "\(stats.received)/\(stats.transmitted), \(Int(stats.lossPercent))% потерь"
        ))

        let avg = stats.avg ?? 0
        let dialog: IntentDialog
        if stats.received == 0 {
            dialog = IntentDialog("\(host) недоступен — 100% потерь.")
        } else {
            dialog = IntentDialog("\(host): \(Int(avg)) мс, потери \(Int(stats.lossPercent))%.")
        }
        return .result(value: avg, dialog: dialog)
    }
}

/// Resolves a host from a saved favorite name or literal value.
struct CheckHostIsUpIntent: AppIntent {
    static let title: LocalizedStringResource = "Хост доступен?"
    static let description = IntentDescription("Возвращает истину, если хост отвечает на ping.")

    @Parameter(title: "Хост или IP", requestValueDialog: "Какой хост проверить?")
    var host: String

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$host) доступен?")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Bool> {
        let stats = try await ICMPPinger().measure(host: host, config: PingConfig(count: 3, interval: 0.3, timeout: 2))
        let up = stats.received > 0
        return .result(value: up, dialog: IntentDialog(up ? "\(host) доступен." : "\(host) недоступен."))
    }
}

/// Registers spoken phrases and Shortcuts app tiles.
struct CheckNetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PingHostIntent(),
            phrases: [
                "Проверить хост в \(.applicationName)",
                "Пинг в \(.applicationName)",
                "\(.applicationName) проверь сеть"
            ],
            shortTitle: "Проверить хост",
            systemImageName: "dot.radiowaves.left.and.right"
        )
        AppShortcut(
            intent: CheckHostIsUpIntent(),
            phrases: [
                "Хост доступен в \(.applicationName)",
                "\(.applicationName) хост онлайн"
            ],
            shortTitle: "Хост доступен?",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: RunBlockingCheckIntent(),
            phrases: [
                "Проверить блокировку в \(.applicationName)",
                "\(.applicationName) проверь блокировки"
            ],
            shortTitle: "Проверить блокировку",
            systemImageName: "hand.raised"
        )
        AppShortcut(
            intent: CheckReachabilityIntent(),
            phrases: [
                "Проверить доступность в \(.applicationName)",
                "\(.applicationName) что недоступно"
            ],
            shortTitle: "Проверить доступность",
            systemImageName: "network"
        )
        AppShortcut(
            intent: CheckPushDeliveryIntent(),
            phrases: [
                "Проверить уведомления в \(.applicationName)",
                "\(.applicationName) почему не приходят уведомления"
            ],
            shortTitle: "Проверить push",
            systemImageName: "bell.badge"
        )
    }
}
