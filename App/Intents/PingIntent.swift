import AppIntents
import NetworkKit

/// Runs a quick ping to a host. Exposed to Siri, Shortcuts and automations
/// (e.g. "when I get home → test the router").
struct PingHostIntent: AppIntent {
    static let title: LocalizedStringResource = "Check host"
    static let description = IntentDescription("Pings the host and reports latency and loss.")
    static let openAppWhenRun = false

    @Parameter(title: "Host or IP", requestValueDialog: "Which host to check?")
    var host: SavedHostEntity

    @Parameter(title: "Number of packets", default: 5)
    var count: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Check \(\.$host)") {
            \.$count
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        let host = host.value
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
        SharedStore.appendHistory(.ping(
            host: host, avg: stats.avg, lossPercent: stats.lossPercent,
            received: stats.received, transmitted: stats.transmitted
        ))

        let avg = stats.avg ?? 0
        let dialog: IntentDialog
        if stats.received == 0 {
            dialog = IntentDialog("\(host) is unreachable — 100% packet loss.")
        } else {
            dialog = IntentDialog("\(host): \(Int(avg)) ms, \(Int(stats.lossPercent))% loss.")
        }
        return .result(value: avg, dialog: dialog)
    }
}

/// Resolves a host from a saved favorite name or literal value.
struct CheckHostIsUpIntent: AppIntent {
    static let title: LocalizedStringResource = "Host reachable?"
    static let description = IntentDescription("Returns true if the host responds to ping.")

    @Parameter(title: "Host or IP", requestValueDialog: "Which host to check?")
    var host: SavedHostEntity

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$host) reachable?")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Bool> {
        let host = host.value
        let stats = try await ICMPPinger().measure(host: host, config: .quick)
        let up = stats.received > 0
        return .result(value: up, dialog: IntentDialog(up ? "\(host) is reachable." : "\(host) is unreachable."))
    }
}

/// Registers spoken phrases and Shortcuts app tiles.
struct CheckNetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PingHostIntent(),
            phrases: [
                "Check host in \(.applicationName)",
                "Ping in \(.applicationName)",
                "\(.applicationName) check the network"
            ],
            shortTitle: "Check host",
            systemImageName: "dot.radiowaves.left.and.right"
        )
        AppShortcut(
            intent: CheckHostIsUpIntent(),
            phrases: [
                "Host reachable in \(.applicationName)",
                "\(.applicationName) host online"
            ],
            shortTitle: "Host reachable?",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: RunBlockingCheckIntent(),
            phrases: [
                "Check for blocking in \(.applicationName)",
                "\(.applicationName) check for blocks"
            ],
            shortTitle: "Check for blocking",
            systemImageName: "hand.raised"
        )
        AppShortcut(
            intent: CheckReachabilityIntent(),
            phrases: [
                "Check reachability in \(.applicationName)",
                "\(.applicationName) what's unavailable"
            ],
            shortTitle: "Check reachability",
            systemImageName: "network"
        )
        AppShortcut(
            intent: CheckPushDeliveryIntent(),
            phrases: [
                "Check notifications in \(.applicationName)",
                "\(.applicationName) why aren't notifications arriving"
            ],
            shortTitle: "Check push",
            systemImageName: "bell.badge"
        )
    }
}
