import AppIntents
import NetworkKit

/// Runs one blocking check from Siri, Shortcuts or an automation.
///
/// The point of exposing these is automation on network change: iOS won't wake
/// the app when Wi-Fi changes, but a personal automation ("when I join network
/// X → run this intent") can.
struct RunBlockingCheckIntent: AppIntent {
    static let title: LocalizedStringResource = "Проверить блокировку"
    static let description = IntentDescription(
        "Запускает одну проверку ограничений и возвращает вердикт с подробностями.",
        categoryName: "Блокировки"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Проверка")
    var check: BlockingCheckChoice

    @Parameter(title: "Домен или хост", default: "")
    var target: String

    static var parameterSummary: some ParameterSummary {
        Summary("Проверить \(\.$check) для \(\.$target)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<CheckOutcome> {
        let kind = check.kind
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        // Checks that take no target ignore it; the rest fall back to their default.
        let host = trimmed.isEmpty ? kind.defaultTarget : trimmed

        let finding = await kind.run(target: host)
        let outcome = CheckOutcome(finding: finding, target: host)

        SharedStore.appendHistory(CheckRecord(
            tool: "blocking.\(check.rawValue)", host: host, timestamp: Date(),
            latencyMillis: nil, lossPercent: nil,
            succeeded: finding.verdict != .restricted,
            detail: finding.headline
        ))

        return .result(value: outcome, dialog: IntentDialog("\(finding.headline). \(finding.detail)"))
    }
}

/// Sweeps a group of hosts and reports what could not be reached.
struct CheckReachabilityIntent: AppIntent {
    static let title: LocalizedStringResource = "Проверить доступность"
    static let description = IntentDescription(
        "Проверяет доступность группы узлов — провайдеров, популярных сервисов или серверов push-уведомлений.",
        categoryName: "Блокировки"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Что проверять")
    var scope: ReachabilityScope

    static var parameterSummary: some ParameterSummary {
        Summary("Проверить доступность: \(\.$scope)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<CheckOutcome> {
        let sweep = ReachabilitySweep()
        let results = await sweep.run(category: scope.category)
        let reachable = results.filter { $0.status == .reachable }.count
        let obstructed = results.filter { $0.status == .obstructed }.count

        let outcome = CheckOutcome()
        outcome.succeeded = obstructed == 0
        outcome.verdict = obstructed == 0 ? "clean" : "restricted"
        outcome.headline = "Доступно \(reachable) из \(results.count)"
        outcome.target = scope.rawValue

        let unreachable = results.filter { $0.status != .reachable }.map(\.target.host)
        outcome.detail = unreachable.isEmpty
            ? "Все узлы отвечают."
            : "Не отвечают: \(unreachable.joined(separator: ", "))"

        return .result(value: outcome, dialog: IntentDialog("\(outcome.headline). \(outcome.detail)"))
    }
}

/// Dedicated push-delivery check.
///
/// "Уведомления не приходят" is a common complaint that users almost never
/// connect to network filtering, so it gets its own phrase rather than hiding
/// behind a parameter.
struct CheckPushDeliveryIntent: AppIntent {
    static let title: LocalizedStringResource = "Проверить push-уведомления"
    static let description = IntentDescription(
        "Проверяет, доступны ли серверы push-уведомлений Apple и Google.",
        categoryName: "Блокировки"
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<CheckOutcome> {
        let sweep = ReachabilitySweep()
        let results = await sweep.run(category: .pushNotification)
        let blocked = results.filter { $0.status != .reachable }

        let outcome = CheckOutcome()
        outcome.succeeded = blocked.isEmpty
        outcome.verdict = blocked.isEmpty ? "clean" : "restricted"
        outcome.target = "push"
        outcome.headline = blocked.isEmpty
            ? "Push-серверы доступны"
            : "Недоступно \(blocked.count) из \(results.count)"
        outcome.detail = blocked.isEmpty
            ? "Apple APNs и Google FCM отвечают — сеть доставку уведомлений не блокирует."
            : "Не отвечают: \(blocked.map(\.target.host).joined(separator: ", "))"

        return .result(value: outcome, dialog: IntentDialog("\(outcome.headline). \(outcome.detail)"))
    }
}
