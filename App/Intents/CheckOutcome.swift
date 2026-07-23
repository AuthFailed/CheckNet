import AppIntents
import NetworkKit

/// Structured result handed back to Shortcuts.
///
/// The original intents returned a bare `Double` or `Bool`, which meant an
/// automation could not branch on anything but that one number. Exposing the
/// fields separately lets a user build "if loss > 20% then notify me" without
/// parsing text.
struct CheckOutcome: TransientAppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Результат проверки")

    @Property(title: "Успешно")
    var succeeded: Bool

    @Property(title: "Вердикт")
    var verdict: String

    @Property(title: "Заголовок")
    var headline: String

    @Property(title: "Подробности")
    var detail: String

    @Property(title: "Цель")
    var target: String

    @Property(title: "Задержка, мс")
    var latencyMillis: Double?

    @Property(title: "Потери, %")
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

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Проверка блокировок")

    static let caseDisplayRepresentations: [BlockingCheckChoice: DisplayRepresentation] = [
        .dnsSpoofing: "Подмена DNS",
        .httpBlock: "Страница-заглушка",
        .sniBlocking: "Блокировка по SNI",
        .ipBlocking: "Блокировка по IP",
        .whitelist: "Белые списки",
        .siberian: "«Сибирская» блокировка",
        .transferCutoff: "Обрыв на 16–20 КБ"
    ]

    /// Dispatch happens in NetworkKit; raw values match one-to-one.
    var kind: CensorshipCheckKind { CensorshipCheckKind(rawValue: rawValue)! }
}

/// Target groups for the reachability sweep.
enum ReachabilityScope: String, AppEnum {
    case foreignProviders, russianProviders, webServices, pushNotifications

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Что проверять")

    static let caseDisplayRepresentations: [ReachabilityScope: DisplayRepresentation] = [
        .foreignProviders: "Зарубежные провайдеры",
        .russianProviders: "Российские провайдеры",
        .webServices: "Популярные сервисы",
        .pushNotifications: "Push-уведомления"
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
