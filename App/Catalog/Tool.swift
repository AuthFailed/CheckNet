import SwiftUI

/// Every diagnostic tool the app offers. `implemented` gates whether a real
/// screen is wired up yet; the rest show a polished "coming soon" scaffold.
enum Tool: String, CaseIterable, Identifiable, Codable {
    // Reachability
    case ping, traceroute, mtr, portScan, tlsInspector
    // DNS
    case dns, dnsCompare, dnsTamper, reverseDns
    // Discovery
    case networkBrowser, ipScanner, bonjour, wakeOnLan
    // Info
    case interfaces, hostToIP, ipLocation, whois, blacklist
    // Performance
    case speedTest, bufferbloat, mtuDiscovery
    // Wi-Fi
    case wifiAnalysis, wifiSignal
    // Advanced
    case worldPing, cgnatDetect, monitoring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ping: return "Ping"
        case .traceroute: return "Трассировка"
        case .mtr: return "MTR"
        case .portScan: return "Проверка портов"
        case .tlsInspector: return "TLS-инспектор"
        case .dns: return "DNS (nslookup)"
        case .dnsCompare: return "Сравнение резолверов"
        case .dnsTamper: return "Детект DNS-подмены"
        case .reverseDns: return "Обратный DNS"
        case .networkBrowser: return "Обзор сети"
        case .ipScanner: return "Сканер IP-диапазона"
        case .bonjour: return "Bonjour / mDNS"
        case .wakeOnLan: return "Wake-on-LAN"
        case .interfaces: return "Сетевые интерфейсы"
        case .hostToIP: return "Host → IP"
        case .ipLocation: return "Геолокация IP"
        case .whois: return "Whois домена"
        case .blacklist: return "Проверка блэклистов"
        case .speedTest: return "Тест скорости"
        case .bufferbloat: return "Bufferbloat"
        case .mtuDiscovery: return "MTU discovery"
        case .wifiAnalysis: return "Wi-Fi анализ"
        case .wifiSignal: return "Сигнал Wi-Fi"
        case .worldPing: return "World Ping"
        case .cgnatDetect: return "CGNAT / Double NAT"
        case .monitoring: return "Мониторинг хостов"
        }
    }

    var subtitle: String {
        switch self {
        case .ping: return "ICMP · задержка, потери, джиттер"
        case .traceroute: return "Путь до хоста по хопам"
        case .mtr: return "Трассировка + непрерывный ping"
        case .portScan: return "TCP-connect по портам"
        case .tlsInspector: return "Сертификаты, TLS, ALPN"
        case .dns: return "Все типы записей, латентность"
        case .dnsCompare: return "Разные резолверы бок о бок"
        case .dnsTamper: return "Подмена и цензура DNS"
        case .reverseDns: return "IP → имя хоста (PTR)"
        case .networkBrowser: return "Устройства в вашей сети"
        case .ipScanner: return "Живые хосты в диапазоне"
        case .bonjour: return "Сервисы mDNS рядом"
        case .wakeOnLan: return "Разбудить устройство по MAC"
        case .interfaces: return "IP, маска, MAC, MTU"
        case .hostToIP: return "Разрешение имени в адрес"
        case .ipLocation: return "Страна, город, ASN"
        case .whois: return "Регистратор, даты, NS"
        case .blacklist: return "IP в DNSBL-списках"
        case .speedTest: return "Скорость загрузки/отдачи"
        case .bufferbloat: return "Рост задержки под нагрузкой"
        case .mtuDiscovery: return "Максимальный размер пакета"
        case .wifiAnalysis: return "RSSI, канал, роуминг"
        case .wifiSignal: return "Уровень сигнала и потери"
        case .worldPing: return "Доступность из разных точек"
        case .cgnatDetect: return "Тип NAT и внешний IP"
        case .monitoring: return "Фоновый аптайм-монитор"
        }
    }

    var systemImage: String {
        switch self {
        case .ping: return "dot.radiowaves.left.and.right"
        case .traceroute: return "point.topleft.down.to.point.bottomright.curvepath"
        case .mtr: return "chart.line.uptrend.xyaxis"
        case .portScan: return "square.grid.3x3.middle.filled"
        case .tlsInspector: return "lock.shield"
        case .dns: return "magnifyingglass"
        case .dnsCompare: return "arrow.left.arrow.right"
        case .dnsTamper: return "exclamationmark.shield"
        case .reverseDns: return "arrow.uturn.backward"
        case .networkBrowser: return "rectangle.connected.to.line.below"
        case .ipScanner: return "barcode.viewfinder"
        case .bonjour: return "bonjour"
        case .wakeOnLan: return "power"
        case .interfaces: return "network"
        case .hostToIP: return "arrow.right.circle"
        case .ipLocation: return "mappin.and.ellipse"
        case .whois: return "doc.text.magnifyingglass"
        case .blacklist: return "hand.raised.slash"
        case .speedTest: return "gauge.with.dots.needle.67percent"
        case .bufferbloat: return "waveform.path.ecg"
        case .mtuDiscovery: return "ruler"
        case .wifiAnalysis: return "wifi"
        case .wifiSignal: return "wifi.circle"
        case .worldPing: return "globe"
        case .cgnatDetect: return "arrow.triangle.branch"
        case .monitoring: return "bell.badge"
        }
    }

    /// A short "what & why" description shown behind the ⓘ button.
    var info: String {
        switch self {
        case .ping:
            return "Отправляет ICMP-эхо на хост и измеряет время отклика, потери пакетов и джиттер. Помогает понять, доступен ли узел и стабильна ли связь до него."
        case .traceroute:
            return "Показывает маршрут пакетов до хоста по шагам (хопам) и задержку на каждом. Помогает найти, на каком участке сети возникают проблемы."
        case .mtr:
            return "Объединяет трассировку и непрерывный ping: постоянно опрашивает каждый хоп и копит статистику потерь и задержек. Аналог WinMTR — удобно ловить нестабильный участок."
        case .portScan:
            return "Проверяет, какие TCP-порты открыты на хосте. Помогает узнать, какие сервисы доступны. Сканирование чужих хостов может расцениваться как недружественное действие."
        case .tlsInspector:
            return "Открывает TLS-соединение и показывает сертификат, цепочку доверия, версию протокола и ALPN. Помогает проверить безопасность и корректность настройки HTTPS."
        case .dns:
            return "Запрашивает у DNS все типы записей домена (A, AAAA, MX, TXT и др.) и показывает задержку резолвера. Базовая диагностика доменных имён."
        case .dnsCompare:
            return "Спрашивает один и тот же домен у нескольких DNS-резолверов и сравнивает ответы бок о бок. Помогает заметить подмену или расхождения."
        case .dnsTamper:
            return "Сравнивает ответ вашего DNS с доверенным и ищет признаки подмены или цензуры. Перенесено во вкладку «Блокировки»."
        case .reverseDns:
            return "По IP-адресу находит связанное с ним доменное имя (PTR-запись). Помогает опознать владельца адреса."
        case .networkBrowser:
            return "Находит устройства в вашей локальной сети и их адреса. Помогает увидеть, что подключено к вашему Wi-Fi."
        case .ipScanner:
            return "Перебирает диапазон IP-адресов и находит живые хосты. Полезно для инвентаризации своей сети. Сканирование чужих сетей может считаться недружественным."
        case .bonjour:
            return "Ищет сервисы Bonjour/mDNS рядом (принтеры, AirPlay, колонки и т. п.). Показывает, что рекламирует себя в вашей сети."
        case .wakeOnLan:
            return "Отправляет «магический пакет» по MAC-адресу, чтобы удалённо разбудить устройство в локальной сети."
        case .interfaces:
            return "Показывает сетевые интерфейсы устройства: IP, маску, MAC и MTU. Базовая информация о вашем подключении."
        case .hostToIP:
            return "Преобразует доменное имя в IP-адрес (и наоборот). Простейшая проверка работы DNS."
        case .ipLocation:
            return "Показывает предполагаемую страну, город и ASN по IP-адресу. Требует внешнего сервиса геолокации."
        case .whois:
            return "Запрашивает данные о регистрации домена: регистратор, даты, серверы имён. Помогает узнать, кому принадлежит домен."
        case .blacklist:
            return "Проверяет, числится ли IP в почтовых чёрных списках (DNSBL). Полезно, если ваша почта попадает в спам."
        case .speedTest:
            return "Измеряет скорость загрузки и отдачи через iperf3-серверы или HTTP. Показывает реальную пропускную способность канала."
        case .bufferbloat:
            return "Измеряет рост задержки под нагрузкой (bufferbloat). Требует нагрузочного сервера."
        case .mtuDiscovery:
            return "Находит максимальный размер пакета, проходящий без фрагментации (Path MTU). Помогает диагностировать обрывы и залипания соединений."
        case .wifiAnalysis:
            return "Анализ Wi-Fi: уровень сигнала, канал, роуминг. Ограничено политиками iOS."
        case .wifiSignal:
            return "Уровень сигнала Wi-Fi и потери. Ограничено политиками iOS."
        case .worldPing:
            return "Проверяет доступность хоста из разных точек мира. Требует внешнего сервиса."
        case .cgnatDetect:
            return "Определяет тип NAT и ваш внешний IP через STUN. Помогает понять, находитесь ли вы за CGNAT (общим адресом провайдера)."
        case .monitoring:
            return "Фоновый монитор доступности хостов: периодически пингует и ведёт историю аптайма."
        }
    }

    /// Tools whose activity could be seen as intrusive on foreign networks
    /// (scanning). Gated behind a one-time consent prompt.
    var isSensitive: Bool {
        switch self {
        case .portScan, .ipScanner:
            return true
        default:
            return false
        }
    }

    /// Tools that now live in the Блокировки tab and must not appear in the
    /// main catalog or search (kept routable for deep links).
    var isCensorshipCheck: Bool { self == .dnsTamper }

    /// Tools with a fully-implemented, tested screen.
    var isImplemented: Bool {
        switch self {
        case .ping, .traceroute, .mtr, .dns, .dnsCompare, .dnsTamper, .portScan, .tlsInspector,
             .hostToIP, .reverseDns, .interfaces, .whois, .blacklist, .wakeOnLan,
             .mtuDiscovery, .ipScanner, .bonjour, .cgnatDetect, .monitoring, .networkBrowser,
             .speedTest:
            return true
        default:
            return false
        }
    }
}

/// A category grouping in the catalog.
struct ToolSection: Identifiable {
    let id: String
    let title: String
    let tools: [Tool]
}

enum ToolCatalog {
    static let sections: [ToolSection] = [
        ToolSection(id: "reach", title: "Доступность", tools: [.ping, .traceroute, .mtr, .portScan, .tlsInspector]),
        ToolSection(id: "dns", title: "DNS", tools: [.dns, .dnsCompare, .reverseDns]),
        ToolSection(id: "discovery", title: "Обнаружение", tools: [.networkBrowser, .ipScanner, .bonjour, .wakeOnLan]),
        ToolSection(id: "info", title: "Информация", tools: [.interfaces, .hostToIP, .ipLocation, .whois, .blacklist]),
        ToolSection(id: "perf", title: "Производительность", tools: [.speedTest, .bufferbloat, .mtuDiscovery]),
        ToolSection(id: "wifi", title: "Wi-Fi", tools: [.wifiAnalysis, .wifiSignal]),
        ToolSection(id: "advanced", title: "Продвинутое", tools: [.worldPing, .cgnatDetect, .monitoring])
    ]

    static func tool(withID id: String) -> Tool? { Tool(rawValue: id) }
}
