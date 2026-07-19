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
}

/// Fetches and parses the auto-updated public iperf3 server list.
/// Source: export.iperf3serverlist.net (regenerated hourly, dead servers removed).
public struct IperfServerList: Sendable {
    public init() {}

    public static let endpoint = "https://export.iperf3serverlist.net/listed_iperf3_servers.json"

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
        return rows.compactMap { row in
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
    }
}
