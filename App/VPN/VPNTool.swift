import SwiftUI

/// Tools in the **VPN** tab — utilities for people who *run* a VPN
/// (Xray / Reality / mihomo / Happ ecosystem), as opposed to the end-user
/// diagnostics in the Тесты tab. Kept as its own type, like `BlockingCheck`,
/// so the main catalog stays about network diagnostics.
///
/// Scope is diagnostics and config management — inspect, parse, build, check.
/// The app performs no DPI-bypass; it helps an operator set up and verify their
/// own server.
enum VPNTool: String, CaseIterable, Identifiable {
    // Links & subscriptions
    case happRouting
    case subscription
    case happDecrypt
    case incyLink
    // Server checks
    case sniCheck
    case realityScanner
    case xrayCheck
    // Lists & data
    case geoData
    case mrsViewer
    case clientHeaders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .happRouting: "Роутинг Happ"
        case .subscription: "Парсинг подписки"
        case .happDecrypt: "Happ Decrypt"
        case .incyLink: "Incy-ссылка"
        case .sniCheck: "Проверка SNI для Reality"
        case .realityScanner: "Сканер для Reality"
        case .xrayCheck: "Доступность Xray"
        case .geoData: "geosite / geoip"
        case .mrsViewer: "Правила mihomo (.mrs)"
        case .clientHeaders: "Заголовки клиентов"
        }
    }

    var subtitle: String {
        switch self {
        case .happRouting: "Разбор и сборка правил роутинга"
        case .subscription: "Хосты и роутинг из подписки"
        case .happDecrypt: "Расшифровка happ://crypt-ссылок"
        case .incyLink: "Разбор и генерация incy://crypt1"
        case .sniCheck: "Годится ли домен под dest"
        case .realityScanner: "Поиск TLS 1.3 доменов в подсети"
        case .xrayCheck: "Живой ли VLESS/Trojan-инбаунд"
        case .geoData: "Просмотр .dat: категории, поиск"
        case .mrsViewer: "Распаковка rule-set в правила"
        case .clientHeaders: "Что отдаёт сервер разным клиентам"
        }
    }

    var systemImage: String {
        switch self {
        case .happRouting: "arrow.triangle.branch"
        case .subscription: "list.bullet.rectangle"
        case .happDecrypt: "lock.open"
        case .incyLink: "link.badge.plus"
        case .sniCheck: "checkmark.shield"
        case .realityScanner: "dot.radiowaves.left.and.right"
        case .xrayCheck: "bolt.horizontal.circle"
        case .geoData: "globe.badge.chevron.backward"
        case .mrsViewer: "doc.plaintext"
        case .clientHeaders: "person.2.badge.gearshape"
        }
    }

    /// The "what & why" shown behind the ⓘ button and, for unbuilt tools, on the
    /// placeholder screen.
    var info: String {
        switch self {
        case .happRouting:
            "Разбирает ссылку `happ://routing/add/…` в читаемый профиль (DNS, стратегия, списки Direct/Proxy/Block) и собирает ссылку обратно. Импорт существующих правил и генерация новых для клиента Happ."
        case .subscription:
            "Разбирает подписку (base64-ссылки, Clash YAML, sing-box JSON, Happ/Incy) и показывает список узлов, параметры и встроенный роутинг с быстрым переходом к проверкам."
        case .happDecrypt:
            "Расшифровывает ссылки `happ://crypt…` (обычно это подписка или конфиг) в читаемый вид. Всё считается на устройстве."
        case .incyLink:
            "Разбирает `incy://crypt1/…` в URL подписки и генерирует такую ссылку из своего URL — чтобы отдавать пользователям ссылку и QR вместо «голого» адреса."
        case .sniCheck:
            "Проверяет, годится ли домен как SNI/dest для Reality: TLS 1.3, HTTP/2, отсутствие редиректа, сертификат, гео и доступность — с итоговым вердиктом."
        case .realityScanner:
            "Обходит IP-адрес, подсеть (CIDR) или домен и находит хосты с TLS 1.3, показывая домен из их сертификата — кандидаты под dest рядом с вашим сервером. Рукопожатие идёт без SNI, как в RealiTLScanner. Только поиск, без обхода блокировок."
        case .xrayCheck:
            "Делает настоящий handshake к вашему инбаунду (VLESS/Trojan) и пробный запрос через сервер, чтобы подтвердить, что он работает, и назвать причину при сбое."
        case .geoData:
            "Открывает ваши файлы `geosite.dat` / `geoip.dat`: категории и теги, поиск домена/IP по категориям, фильтры и сортировка, экспорт."
        case .mrsViewer:
            "Распаковывает скомпилированный rule-set mihomo (`.mrs`) обратно в список доменов или подсетей с поиском и экспортом."
        case .clientHeaders:
            "Запрашивает вашу подписку с заголовками разных клиентов (Happ, Clash-семейство, sing-box…) и показывает, что сервер отдаёт каждому, с группировкой по типу клиента."
        }
    }

    /// Tools with a fully-implemented, tested screen. Exhaustive on purpose: a
    /// new tool must answer "is this done?" at the compiler, not ship silently
    /// as a placeholder.
    var isImplemented: Bool {
        switch self {
        case .happRouting, .happDecrypt, .incyLink, .subscription, .sniCheck, .realityScanner, .clientHeaders, .geoData, .xrayCheck:
            return true
        case .mrsViewer:
            return false
        }
    }
}

/// Groups the VPN tools in the landing list.
struct VPNSection: Identifiable {
    let id: String
    let title: String
    let tools: [VPNTool]
}

enum VPNCatalog {
    static let sections: [VPNSection] = [
        VPNSection(id: "links", title: "Ссылки и подписки",
                   tools: [.happRouting, .subscription, .happDecrypt, .incyLink]),
        VPNSection(id: "server", title: "Проверки сервера",
                   tools: [.sniCheck, .realityScanner, .xrayCheck]),
        VPNSection(id: "data", title: "Списки и данные",
                   tools: [.geoData, .mrsViewer, .clientHeaders]),
    ]
}
