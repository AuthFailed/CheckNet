import AppIntents
import NetworkKit

/// Structured result handed back to Shortcuts.
///
/// The original intents returned a bare `Double` or `Bool`, which meant an
/// automation could not branch on anything but that one number. Exposing the
/// fields separately lets a user build "if loss > 20% then notify me" without
/// parsing text.
struct CheckOutcome: TransientAppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Check result")

    @Property(title: "Success")
    var succeeded: Bool

    @Property(title: "Verdict")
    var verdict: String

    @Property(title: "Title")
    var headline: String

    @Property(title: "Details")
    var detail: String

    @Property(title: "Target")
    var target: String

    @Property(title: "Latency, ms")
    var latencyMillis: Double?

    @Property(title: "Loss, %")
    var lossPercent: Double?

    init() {}

    init(finding: CensorshipFinding, target: String) {
        self.init()
        self.succeeded = finding.verdict != .restricted
        self.verdict = finding.verdict.rawValue
        self.headline = finding.headline
        self.detail = finding.detail
        self.target = target
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(headline)", subtitle: "\(detail)")
    }
}

/// Blocking checks, as a Shortcuts-selectable list.
enum BlockingCheckChoice: String, AppEnum {
    case dnsSpoofing, httpBlock, sniBlocking, ipBlocking, whitelist, siberian, transferCutoff

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Blocking check")

    static let caseDisplayRepresentations: [BlockingCheckChoice: DisplayRepresentation] = [
        .dnsSpoofing: "DNS spoofing",
        .httpBlock: "Stub page",
        .sniBlocking: "SNI-based block",
        .ipBlocking: "IP-based block",
        .whitelist: "Whitelists",
        .siberian: "“Siberian” block",
        .transferCutoff: "Cut off at 16–20 KB"
    ]

    /// Dispatch happens in NetworkKit; raw values match one-to-one.
    var kind: CensorshipCheckKind { CensorshipCheckKind(rawValue: rawValue)! }
}

/// Target groups for the reachability sweep.
enum ReachabilityScope: String, AppEnum {
    case foreignProviders, russianProviders, webServices, pushNotifications

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "What to check")

    static let caseDisplayRepresentations: [ReachabilityScope: DisplayRepresentation] = [
        .foreignProviders: "International providers",
        .russianProviders: "Russian providers",
        .webServices: "Popular services",
        .pushNotifications: "Push notifications"
    ]

    var category: ProbeTarget.Category {
        switch self {
        case .foreignProviders: .foreignInfrastructure
        case .russianProviders: .russianInfrastructure
        case .webServices: .webService
        case .pushNotifications: .pushNotification
        }
    }
}
