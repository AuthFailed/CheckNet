import AppIntents
import NetworkKit

/// Runs one blocking check from Siri, Shortcuts or an automation.
///
/// The point of exposing these is automation on network change: iOS won't wake
/// the app when Wi-Fi changes, but a personal automation ("when I join network
/// X → run this intent") can.
struct RunBlockingCheckIntent: AppIntent {
    static let title: LocalizedStringResource = "Check for blocking"
    static let description = IntentDescription(
        "Runs a single restriction check and returns a verdict with details.",
        categoryName: "Blocks"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Check")
    var check: BlockingCheckChoice

    @Parameter(title: "Domain or host")
    var target: SavedHostEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Check \(\.$check) for \(\.$target)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<CheckOutcome> {
        let kind = check.kind
        let trimmed = (target?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Checks that take no target ignore it; the rest fall back to their default.
        let host = trimmed.isEmpty ? kind.defaultTarget : trimmed

        let finding = await kind.run(target: host)
        let outcome = CheckOutcome(finding: finding, target: host)

        SharedStore.appendHistory(.blocking(
            checkID: check.rawValue, host: host, headline: finding.headline,
            restricted: finding.verdict == .restricted
        ))

        return .result(value: outcome, dialog: IntentDialog("\(finding.headline). \(finding.detail)"))
    }
}

/// Sweeps a group of hosts and reports what could not be reached.
struct CheckReachabilityIntent: AppIntent {
    static let title: LocalizedStringResource = "Check reachability"
    static let description = IntentDescription(
        "Checks whether a group of hosts is reachable — providers, popular services or push notification servers.",
        categoryName: "Blocks"
    )
    static let openAppWhenRun = false

    @Parameter(title: "What to check")
    var scope: ReachabilityScope

    static var parameterSummary: some ParameterSummary {
        Summary("Check reachability: \(\.$scope)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<CheckOutcome> {
        let sweep = ReachabilitySweep()
        let results = await sweep.run(category: scope.category)
        let reachable = results.filter { $0.status == .reachable }.count
        let obstructed = results.filter { $0.status == .obstructed }.count

        let outcome = CheckOutcome()
        outcome.succeeded = obstructed == 0
        outcome.verdict = obstructed == 0 ? "clean" : "restricted"
        outcome.headline = "\(reachable) of \(results.count) reachable"
        outcome.target = scope.rawValue

        let unreachable = results.filter { $0.status != .reachable }.map(\.target.host)
        outcome.detail = unreachable.isEmpty
            ? "All hosts respond."
            : "Not responding: \(unreachable.joined(separator: ", "))"

        return .result(value: outcome, dialog: IntentDialog("\(outcome.headline). \(outcome.detail)"))
    }
}

/// Dedicated push-delivery check.
///
/// "Notifications aren't arriving" is a common complaint that users almost never
/// connect to network filtering, so it gets its own phrase rather than hiding
/// behind a parameter.
struct CheckPushDeliveryIntent: AppIntent {
    static let title: LocalizedStringResource = "Check push notifications"
    static let description = IntentDescription(
        "Checks reachability of push notification servers (APNs and FCM).",
        categoryName: "Blocks"
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
            ? "Push servers are reachable"
            : "\(blocked.count) of \(results.count) unavailable"
        outcome.detail = blocked.isEmpty
            ? "APNs and FCM servers respond — the network isn't blocking notification delivery."
            : "Not responding: \(blocked.map(\.target.host).joined(separator: ", "))"

        return .result(value: outcome, dialog: IntentDialog("\(outcome.headline). \(outcome.detail)"))
    }
}
