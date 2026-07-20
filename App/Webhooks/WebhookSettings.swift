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
        case .blockingOnly: event.hasPrefix("blocking.")
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

    /// Outcome of the most recent delivery, shown in settings so a misconfigured
    /// endpoint is visible instead of failing silently.
    private(set) var lastStatus: String?

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let enabled = "checknet.webhook.enabled"
        static let url = "checknet.webhook.url"
        static let secret = "checknet.webhook.secret"
        static let trigger = "checknet.webhook.trigger"
    }

    init() {
        isEnabled = defaults.bool(forKey: Keys.enabled)
        urlString = defaults.string(forKey: Keys.url) ?? ""
        secret = defaults.string(forKey: Keys.secret) ?? ""
        trigger = WebhookTrigger(rawValue: defaults.string(forKey: Keys.trigger) ?? "") ?? .allChecks
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
        let dispatcher = WebhookDispatcher(url: url, secret: secret)
        let event = WebhookEvent(
            event: "test.ping", host: "1.1.1.1", succeeded: true,
            verdict: "clean", headline: "Тестовое событие",
            detail: "Проверка настройки вебхука", latencyMillis: 12.0, lossPercent: 0,
            metadata: ["source": "settings"]
        )
        let delivery = await dispatcher.send(event)
        lastStatus = delivery.succeeded
            ? "Доставлено, ответ \(delivery.statusCode ?? 200)."
            : "Не доставлено: \(delivery.error ?? "неизвестная ошибка")."
    }
}

/// Fire-and-forget reporting from anywhere a check completes.
@MainActor
enum WebhookReporter {
    /// Set once at app start; nil means webhooks aren't configured.
    static weak var settings: WebhookSettings?

    static func report(
        event: String, host: String, succeeded: Bool,
        verdict: String? = nil, headline: String? = nil, detail: String? = nil,
        latencyMillis: Double? = nil, lossPercent: Double? = nil
    ) {
        guard let settings, settings.isEnabled,
              settings.trigger.allows(event: event, succeeded: succeeded),
              let url = settings.validatedURL
        else { return }

        let dispatcher = WebhookDispatcher(url: url, secret: settings.secret)
        let payload = WebhookEvent(
            event: event, host: host, succeeded: succeeded,
            verdict: verdict, headline: headline, detail: detail,
            latencyMillis: latencyMillis, lossPercent: lossPercent
        )
        // Detached so a slow or dead receiver never stalls the UI.
        Task.detached {
            let delivery = await dispatcher.send(payload)
            await MainActor.run {
                settings.setStatus(delivery.succeeded
                    ? "Отправлено: \(event)"
                    : "Ошибка отправки \(event): \(delivery.error ?? "-")")
            }
        }
    }
}
