import Foundation
import Observation
import NetworkKit

/// Which results get sent out.
enum WebhookTrigger: String, CaseIterable, Identifiable, Codable {
    case allChecks, failuresOnly, blockingOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allChecks: "Все проверки"
        case .failuresOnly: "Только проблемы"
        case .blockingOnly: "Только блокировки"
        }
    }

    func allows(event: String, succeeded: Bool) -> Bool {
        switch self {
        case .allChecks: true
        case .failuresOnly: !succeeded
        // Profile runs are blocking checks under a different prefix.
        case .blockingOnly: event.hasPrefix("blocking.") || event.hasPrefix("profile.")
        }
    }
}

/// User configuration for outgoing webhooks.
///
/// Off by default: sending measurements to a third-party server is a
/// disclosure, so it only happens after the user has entered an address and
/// switched it on themselves.
@MainActor
@Observable
final class WebhookSettings {
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled) }
    }
    var urlString: String {
        didSet { defaults.set(urlString, forKey: Keys.url) }
    }
    var secret: String {
        didSet { defaults.set(secret, forKey: Keys.secret) }
    }
    var trigger: WebhookTrigger {
        didSet { defaults.set(trigger.rawValue, forKey: Keys.trigger) }
    }
    var format: WebhookFormat {
        didSet { defaults.set(format.rawValue, forKey: Keys.format) }
    }
    /// Send intermediate results while a test is still running, not just the
    /// final result. Off by default — it's a stream of extra requests.
    var liveMode: Bool {
        didSet { defaults.set(liveMode, forKey: Keys.liveMode) }
    }

    /// Per-tool field selection. Absent tool ⇒ that tool's schema default
    /// (everything on), so it works natively until the user narrows it.
    private var fieldSelection: [String: Set<String>] {
        didSet { persistSelection() }
    }

    /// Outcome of the most recent delivery, shown in settings so a misconfigured
    /// endpoint is visible instead of failing silently.
    private(set) var lastStatus: String?

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let enabled = "checknet.webhook.enabled"
        static let url = "checknet.webhook.url"
        static let secret = "checknet.webhook.secret"
        static let trigger = "checknet.webhook.trigger"
        static let format = "checknet.webhook.format"
        static let selection = "checknet.webhook.fields"
        static let liveMode = "checknet.webhook.live"
    }

    init() {
        isEnabled = defaults.bool(forKey: Keys.enabled)
        urlString = defaults.string(forKey: Keys.url) ?? ""
        secret = defaults.string(forKey: Keys.secret) ?? ""
        trigger = WebhookTrigger(rawValue: defaults.string(forKey: Keys.trigger) ?? "") ?? .allChecks
        format = WebhookFormat(rawValue: defaults.string(forKey: Keys.format) ?? "") ?? .jsonNested
        liveMode = defaults.bool(forKey: Keys.liveMode)
        fieldSelection = defaults.json([String: Set<String>].self, forKey: Keys.selection) ?? [:]
    }

    // MARK: - Field selection

    /// The selected paths for a tool, defaulting to its schema's all-on set.
    func selectedFields(forTool toolKey: String) -> Set<String> {
        if let stored = fieldSelection[toolKey] { return stored }
        return WebhookCatalog.schema(for: toolKey)?.defaultPaths ?? []
    }

    func isFieldSelected(toolKey: String, path: String) -> Bool {
        selectedFields(forTool: toolKey).contains(path)
    }

    func setField(toolKey: String, path: String, on: Bool) {
        var set = selectedFields(forTool: toolKey)
        if on { set.insert(path) } else { set.remove(path) }
        fieldSelection[toolKey] = set
    }

    /// Restores a tool to its native default (all fields on).
    func resetFields(forTool toolKey: String) {
        fieldSelection[toolKey] = nil
    }

    private func persistSelection() {
        defaults.setJSON(fieldSelection, forKey: Keys.selection)
    }

    // MARK: - Secret

    /// Generates a fresh 32-byte random secret, hex-encoded.
    func generateSecret() {
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        secret = bytes.map { String(format: "%02x", $0) }.joined()
    }

    func clearSecret() {
        secret = ""
    }

    /// Validated endpoint, or nil when the current text isn't usable.
    var validatedURL: URL? {
        try? WebhookDispatcher.validate(urlString: urlString)
    }

    var validationMessage: String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            _ = try WebhookDispatcher.validate(urlString: trimmed)
            return nil
        } catch WebhookDispatcher.DispatchError.insecureScheme {
            return "http допустим только для localhost — иначе результаты уйдут в открытом виде."
        } catch {
            return "Не похоже на корректный адрес."
        }
    }

    func setStatus(_ text: String) {
        lastStatus = text
    }

    /// Sends a sample event so the user can confirm the receiver works before
    /// relying on it.
    func sendTestEvent() async {
        guard let url = validatedURL else {
            lastStatus = "Адрес не задан или некорректен."
            return
        }
        // Build the test event with the user's chosen format and ping field
        // selection, so the sample matches what real deliveries will look like.
        let schema = WebhookCatalog.ping
        let values = WebhookCatalog.pingValues(
            PingStatistics(host: "1.1.1.1", resolvedIP: "1.1.1.1", transmitted: 3, received: 3, rttSamples: [11, 12, 10]),
            samples: []
        )
        let (body, contentType) = WebhookPayloadBuilder.build(
            schema: schema, values: values,
            selected: selectedFields(forTool: schema.toolKey),
            envelope: WebhookReporter.envelope(event: "test.ping", succeeded: true),
            format: format
        )
        let dispatcher = WebhookDispatcher(url: url, secret: secret)
        let delivery = await dispatcher.send(body: body, contentType: contentType, eventName: "test.ping")
        lastStatus = delivery.succeeded
            ? "Доставлено, ответ \(delivery.statusCode ?? 200)."
            : "Не доставлено: \(delivery.error ?? "неизвестная ошибка")."
    }
}

/// Fire-and-forget reporting from anywhere a check completes.
///
/// Assembles the payload from the tool's schema, the user's field selection and
/// the chosen format — so which fields go out, and in what shape, is the user's
/// choice while defaulting to the full native result.
@MainActor
enum WebhookReporter {
    /// Set once at app start; nil means webhooks aren't configured.
    static weak var settings: WebhookSettings?

    /// Envelope carried on every event regardless of tool. This is metadata, not
    /// measurement data, so it's always present.
    static func envelope(event: String, succeeded: Bool) -> [String: WebhookValue] {
        [
            "version": .int(WebhookEvent.currentVersion),
            "event": .string(event),
            "succeeded": .bool(succeeded),
            "timestamp": .date(Date())
        ]
    }

    /// The core reporter: a tool key (for schema + selection), an event name and
    /// the tool's values.
    static func report(toolKey: String, event: String, succeeded: Bool, values: [String: WebhookValue]) {
        guard let settings, settings.isEnabled,
              settings.trigger.allows(event: event, succeeded: succeeded),
              let url = settings.validatedURL,
              let schema = WebhookCatalog.schema(for: toolKey)
        else { return }

        let (body, contentType) = WebhookPayloadBuilder.build(
            schema: schema, values: values,
            selected: settings.selectedFields(forTool: toolKey),
            envelope: envelope(event: event, succeeded: succeeded),
            format: settings.format
        )
        let dispatcher = WebhookDispatcher(url: url, secret: settings.secret)
        // Detached so a slow or dead receiver never stalls the UI.
        Task.detached {
            let delivery = await dispatcher.send(body: body, contentType: contentType, eventName: event)
            await MainActor.run {
                settings.setStatus(delivery.succeeded
                    ? "Отправлено: \(event)"
                    : "Ошибка отправки \(event): \(delivery.error ?? "-")")
            }
        }
    }

    // MARK: - Typed helpers

    static func reportPing(_ stats: PingStatistics, samples: [PingReply]) {
        report(toolKey: "ping", event: "check.ping",
               succeeded: stats.received > 0,
               values: WebhookCatalog.pingValues(stats, samples: samples))
    }

    /// A live, mid-run snapshot. Only fires when live mode is on; the event name
    /// distinguishes it from the final `check.ping`.
    static func reportPingLive(_ stats: PingStatistics, samples: [PingReply]) {
        guard settings?.liveMode == true else { return }
        report(toolKey: "ping", event: "check.ping.live",
               succeeded: stats.received > 0,
               values: WebhookCatalog.pingValues(stats, samples: samples))
    }

    static func reportBlocking(check: String, target: String, finding: CensorshipFinding, eventPrefix: String = "blocking") {
        report(toolKey: "blocking", event: "\(eventPrefix).\(check)",
               succeeded: finding.verdict != .restricted,
               values: WebhookCatalog.blockingValues(check: check, target: target, finding: finding))
    }

    static func reportReachability(scope: String, results: [ReachabilityResult], verdict: String) {
        report(toolKey: "reachability", event: "reachability.\(scope)",
               succeeded: verdict != "restricted",
               values: WebhookCatalog.reachabilityValues(scope: scope, results: results, verdict: verdict))
    }
}
