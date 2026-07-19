import Foundation

/// A DNS-over-HTTPS client (JSON API, RFC 8484 style) used as a trusted,
/// tamper-resistant reference resolver for censorship comparisons.
public struct DoHClient: Sendable {
    public init() {}

    public struct Answer: Sendable, Hashable {
        public let name: String
        public let type: Int
        public let data: String
    }

    /// Resolves A records via Cloudflare DoH (https://1.1.1.1/dns-query).
    public func resolveA(_ name: String, timeout: TimeInterval = 6.0) async throws -> [String] {
        let answers = try await query(name: name, type: "A", timeout: timeout)
        return answers.filter { $0.type == 1 }.map { $0.data }
    }

    public func query(name: String, type: String, timeout: TimeInterval = 6.0) async throws -> [Answer] {
        var comps = URLComponents(string: "https://1.1.1.1/dns-query")!
        comps.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "type", value: type)
        ]
        guard let url = comps.url else { throw NetworkError.invalidHost(name) }
        var request = URLRequest(url: url)
        request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NetworkError.protocolError("DoH HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.protocolError("некорректный DoH JSON")
        }
        let rawAnswers = (json["Answer"] as? [[String: Any]]) ?? []
        return rawAnswers.compactMap { entry in
            guard let n = entry["name"] as? String,
                  let t = entry["type"] as? Int,
                  let d = entry["data"] as? String else { return nil }
            return Answer(name: n, type: t, data: d)
        }
    }
}
