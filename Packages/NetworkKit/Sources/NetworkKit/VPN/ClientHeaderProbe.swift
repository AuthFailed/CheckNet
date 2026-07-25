import Foundation

/// Traffic/quota line a panel sends back in the `subscription-userinfo` header.
public struct SubscriptionUserInfo: Sendable, Hashable, Codable {
    public let uploadBytes: Int64?
    public let downloadBytes: Int64?
    public let totalBytes: Int64?
    public let expire: Date?

    public var hasData: Bool {
        uploadBytes != nil || downloadBytes != nil || totalBytes != nil || expire != nil
    }
}

/// What one client's request to a subscription URL produced.
public struct ClientProbeResult: Sendable, Hashable, Codable, Identifiable {
    public var id: String { clientID }
    public let clientID: String
    public let clientLabel: String
    public let userAgent: String

    public let statusCode: Int
    public let contentType: String?
    public let byteCount: Int
    /// Detected subscription format ("clash", "base64List"…), or nil if unparseable.
    public let format: String?
    public let nodeCount: Int

    // Panel metadata headers (all optional — most panels send a subset).
    public let filename: String?
    public let title: String?
    public let updateIntervalHours: Double?
    public let userInfo: SubscriptionUserInfo?
    public let supportURL: String?

    public let errorText: String?

    /// A request is "good" when the server answered 2xx with at least one node.
    public var isServed: Bool { errorText == nil && (200..<300).contains(statusCode) && nodeCount > 0 }
}

public enum ClientProbeEvent: Sendable {
    case result(ClientProbeResult)
    case finished(servedCount: Int, total: Int)
    case failed(String)
}

/// Requests a subscription URL as each VPN client in turn and reports what the
/// server hands back — status, node count, format, and the panel headers
/// (`subscription-userinfo`, `content-disposition`, `profile-*`). Panels often
/// serve different content, or a 403 page, depending on the `User-Agent`; this
/// makes that visible to an operator. Diagnostics only — it just replays the
/// operator's own subscription with different client identities.
public enum ClientHeaderProbe {
    /// Concrete clients to try (Auto is excluded — this compares real clients).
    public static var defaultClients: [SubscriptionUserAgent] {
        SubscriptionUserAgents.all.filter { $0.header != nil }
    }

    public static func probe(
        urlString: String,
        clients: [SubscriptionUserAgent] = defaultClients,
        timeout: TimeInterval = 15
    ) -> AsyncStream<ClientProbeEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)),
                  url.scheme == "http" || url.scheme == "https" else {
                continuation.yield(.failed("Некорректный URL подписки"))
                continuation.finish()
                return
            }

            let task = Task {
                var served = 0
                await withTaskGroup(of: ClientProbeResult.self) { group in
                    for client in clients {
                        group.addTask { await one(url: url, client: client, timeout: timeout) }
                    }
                    for await result in group {
                        if Task.isCancelled { break }
                        if result.isServed { served += 1 }
                        continuation.yield(.result(result))
                    }
                }
                continuation.yield(.finished(servedCount: served, total: clients.count))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func one(url: URL, client: SubscriptionUserAgent, timeout: TimeInterval) async -> ClientProbeResult {
        let ua = client.header ?? "CheckNet"
        var req = URLRequest(url: url)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = timeout

        func failure(_ text: String) -> ClientProbeResult {
            ClientProbeResult(
                clientID: client.id, clientLabel: client.label, userAgent: ua,
                statusCode: 0, contentType: nil, byteCount: 0, format: nil, nodeCount: 0,
                filename: nil, title: nil, updateIntervalHours: nil, userInfo: nil,
                supportURL: nil, errorText: text
            )
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return failure("нет HTTP-ответа") }
            let headers = normalized(http.allHeaderFields)
            let body = String(data: data, encoding: .utf8) ?? ""
            let parsed = SubscriptionParser.parse(body)

            return ClientProbeResult(
                clientID: client.id, clientLabel: client.label, userAgent: ua,
                statusCode: http.statusCode,
                contentType: headers["content-type"],
                byteCount: data.count,
                format: parsed.nodes.isEmpty ? nil : parsed.format.rawValue,
                nodeCount: parsed.nodes.count,
                filename: filename(from: headers["content-disposition"]),
                title: title(from: headers["profile-title"]),
                updateIntervalHours: headers["profile-update-interval"].flatMap { Double($0) },
                userInfo: userInfo(from: headers["subscription-userinfo"]),
                supportURL: headers["support-url"] ?? headers["profile-web-page-url"],
                errorText: nil
            )
        } catch {
            let ns = error as NSError
            return failure(ns.code == NSURLErrorTimedOut ? "таймаут" : ns.localizedDescription)
        }
    }

    // MARK: - Header parsing

    static func normalized(_ raw: [AnyHashable: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in raw {
            if let key = k as? String { out[key.lowercased()] = "\(v)" }
        }
        return out
    }

    /// Parses `upload=1; download=2; total=3; expire=1700000000` in any order.
    static func userInfo(from header: String?) -> SubscriptionUserInfo? {
        guard let header, !header.isEmpty else { return nil }
        var map: [String: Int64] = [:]
        for pair in header.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let key = kv[0].trimmingCharacters(in: .whitespaces).lowercased()
            if let value = Int64(kv[1].trimmingCharacters(in: .whitespaces)) { map[key] = value }
        }
        guard !map.isEmpty else { return nil }
        // Panels send expire=0 to mean "never expires" — don't render that as 1970.
        let expire = map["expire"].flatMap { $0 == 0 ? nil : Date(timeIntervalSince1970: TimeInterval($0)) }
        return SubscriptionUserInfo(
            uploadBytes: map["upload"], downloadBytes: map["download"],
            totalBytes: map["total"], expire: expire
        )
    }

    /// `attachment; filename="foo.yaml"` or RFC 5987 `filename*=UTF-8''foo`.
    static func filename(from header: String?) -> String? {
        guard let header else { return nil }
        for part in header.split(separator: ";") {
            let p = part.trimmingCharacters(in: .whitespaces)
            if p.lowercased().hasPrefix("filename*=") {
                let raw = String(p.dropFirst("filename*=".count))
                if let enc = raw.range(of: "''") {
                    let pct = String(raw[enc.upperBound...])
                    return pct.removingPercentEncoding ?? pct
                }
            }
            if p.lowercased().hasPrefix("filename=") {
                var name = String(p.dropFirst("filename=".count))
                name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !name.isEmpty { return name }
            }
        }
        return nil
    }

    /// `profile-title` is sometimes plain, sometimes `base64:<...>`.
    static func title(from header: String?) -> String? {
        guard let header, !header.isEmpty else { return nil }
        if header.lowercased().hasPrefix("base64:") {
            let b64 = String(header.dropFirst("base64:".count))
            if let data = Data(base64Encoded: b64), let s = String(data: data, encoding: .utf8) { return s }
        }
        return header
    }
}
