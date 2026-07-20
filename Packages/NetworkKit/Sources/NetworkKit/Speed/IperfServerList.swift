import Foundation

/// A public iperf3 server entry.
public struct IperfServer: Sendable, Hashable, Codable, Identifiable {
    public var id: String { "\(host):\(portRange)" }
    public let host: String
    public let portRange: String     // e.g. "5201" or "5201-5210"
    public let options: String       // supported flags, e.g. "-R,-u"
    public let gbps: String          // link capacity
    public let continent: String
    public let country: String       // ISO code
    public let site: String          // city
    public let provider: String

    /// Whether the server advertises reverse (download) support.
    public var supportsReverse: Bool { options.contains("-R") }

    /// First port from the (possibly ranged) port field.
    public var port: Int {
        let first = portRange.split(separator: "-").first.map(String.init) ?? portRange
        return Int(first.trimmingCharacters(in: .whitespaces)) ?? 5201
    }

    /// All ports in the advertised range (capped).
    public var ports: [Int] {
        let parts = portRange.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2, parts[1] >= parts[0], parts[1] - parts[0] < 64 {
            return Array(parts[0]...parts[1])
        }
        return [port]
    }

    public var locationLabel: String {
        [site, country].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Advertised link capacity, number only (e.g. "1", "10"). Nil when unknown.
    /// Display it as `Text("\(bandwidthValue) Гбит/с")` so the unit localizes.
    public var bandwidthValue: String? {
        let g = gbps.trimmingCharacters(in: .whitespaces)
        guard !g.isEmpty, g != "0" else { return nil }
        let number = g.replacingOccurrences(of: "G", with: "", options: .caseInsensitive)
                      .trimmingCharacters(in: .whitespaces)
        return number.isEmpty ? g : number
    }

    /// Advertised link capacity as a display string, e.g. "1 Гбит/с". Nil when unknown.
    public var bandwidthLabel: String? {
        bandwidthValue.map { "\($0) Гбит/с" }
    }
}

/// Fetches and parses the auto-updated public iperf3 server list.
/// Source: export.iperf3serverlist.net (regenerated hourly, dead servers removed).
public struct IperfServerList: Sendable {
    public init() {}

    public static let endpoint = "https://export.iperf3serverlist.net/listed_iperf3_servers.json"

    /// Curated iperf3 endpoints of the Russian operator «ЭР-Телеком» (Дом.ру),
    /// which are usually not present in the international public list. Named
    /// `st.<city>.ertelecom.ru`. Unreachable entries simply fail the ping probe
    /// and show no latency, so a stale hostname degrades gracefully.
    public static let ertelecomServers: [IperfServer] = {
        let cities: [(host: String, site: String)] = [
            ("st.perm.ertelecom.ru", "Пермь"),
            ("st.tyumen.ertelecom.ru", "Тюмень"),
            ("st.ekb.ertelecom.ru", "Екатеринбург"),
            ("st.chelyabinsk.ertelecom.ru", "Челябинск"),
            ("st.izhevsk.ertelecom.ru", "Ижевск"),
            ("st.kirov.ertelecom.ru", "Киров"),
            ("st.kazan.ertelecom.ru", "Казань"),
            ("st.samara.ertelecom.ru", "Самара"),
            ("st.volgograd.ertelecom.ru", "Волгоград"),
            ("st.nnov.ertelecom.ru", "Нижний Новгород"),
            ("st.krasnodar.ertelecom.ru", "Краснодар"),
            ("st.rostov.ertelecom.ru", "Ростов-на-Дону"),
            ("st.spb.ertelecom.ru", "Санкт-Петербург"),
            ("st.omsk.ertelecom.ru", "Омск"),
            ("st.novosibirsk.ertelecom.ru", "Новосибирск"),
            ("st.ufa.ertelecom.ru", "Уфа"),
            ("st.voronezh.ertelecom.ru", "Воронеж"),
            ("st.krasnoyarsk.ertelecom.ru", "Красноярск")
        ]
        return cities.map {
            IperfServer(host: $0.host, portRange: "5201-5210", options: "-R,-4",
                        gbps: "10", continent: "Europe", country: "RU",
                        site: $0.site, provider: "ЭР-Телеком (Дом.ру)")
        }
    }()

    public func fetch(timeout: TimeInterval = 12) async throws -> [IperfServer] {
        guard let url = URL(string: Self.endpoint) else { throw NetworkError.invalidHost(Self.endpoint) }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NetworkError.protocolError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.protocolError("некорректный JSON списка серверов")
        }
        let parsed: [IperfServer] = rows.compactMap { row in
            func s(_ keys: String...) -> String {
                for k in keys { if let v = row[k] as? String { return v.trimmingCharacters(in: .whitespaces) } }
                return ""
            }
            let host = s("IP/HOST", "HOST", "IP")
            guard !host.isEmpty else { return nil }
            return IperfServer(
                host: host,
                portRange: s("PORT").isEmpty ? "5201" : s("PORT"),
                options: s("OPTIONS"),
                gbps: s("GB/S", "GBPS"),
                continent: s("CONTINENT"),
                country: s("COUNTRY"),
                site: s("SITE"),
                provider: s("PROVIDER")
            )
        }
        // Merge in the curated ErTelecom endpoints (skip any already listed).
        let known = Set(parsed.map(\.host))
        let extras = Self.ertelecomServers.filter { !known.contains($0.host) }
        return parsed + extras
    }
}
