import Foundation
import Network

/// What a single "what's my IP" resource reported about the egress side of the
/// tunnel: the IP it saw, plus whatever geo/ASN it attributes to it.
public struct EgressInfo: Sendable, Equatable {
    public var ip: String
    public var country: String?   // ISO code where we can get one, else a name
    public var asn: String?       // "AS####" (+ name if the source bundles it)
    public var org: String?       // ISP / organisation
    public var note: String?      // extra the source volunteers (e.g. Cloudflare colo)

    public init(ip: String, country: String? = nil, asn: String? = nil, org: String? = nil, note: String? = nil) {
        self.ip = ip; self.country = country; self.asn = asn; self.org = org; self.note = note
    }
}

/// One resource's answer, streamed as it lands.
public struct EgressResult: Sendable, Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let category: String
    public let url: String
    public var info: EgressInfo?
    public var error: String?
    public var millis: Double
    public var ok: Bool { info != nil }
}

/// A resource we ask, through the proxy, "what IP do you see?" — declared so the
/// catalog stays data, not code: `kind` says how to read the body.
public struct EgressResource: Sendable {
    public enum Kind: Sendable {
        case plain                                             // body is the IP
        case trace                                             // Cloudflare key=value lines
        case json(ip: [String], country: [String], asn: [String], org: [String])
    }
    public let name: String
    public let category: String
    public let url: String
    public let kind: Kind
}

/// Sends requests **through a local SOCKS5 inbound** (a running Xray core) to a
/// spread of IP-echo / geo services and reports the egress IP each one sees — so
/// an operator can confirm the exit IP, spot split routing (different sources
/// seeing different IPs) and read the geo/ASN their server presents to the world.
///
/// The whole `URLSession` is pinned to the SOCKS proxy via Network's
/// `ProxyConfiguration` (iOS 17+), so TLS, redirects and JSON all ride the tunnel
/// end-to-end — that is what lets us include Cloudflare's own view over HTTPS.
public enum EgressIPProbe {
    /// Runs the resources through the proxy in a **staggered sliding window** —
    /// at most `maxInFlight` requests share the tunnel at once, and the initial
    /// burst is spaced by `staggerMillis` — yielding each answer as it arrives.
    /// Bounding concurrency keeps one request from queuing behind eighteen others
    /// (which is what made every latency read the same ~timeout value); each
    /// request is timed from its own launch. Cancelling the consumer tears down.
    public static func stream(
        socksPort: Int,
        resources: [EgressResource] = EgressResource.catalog,
        timeout: TimeInterval = 12,
        maxInFlight: Int = 5,
        staggerMillis: UInt64 = 100
    ) -> AsyncStream<EgressResult> {
        AsyncStream { continuation in
            let work = Task {
                let session = makeSession(socksPort: socksPort, timeout: timeout)
                defer { session.invalidateAndCancel() }
                await withTaskGroup(of: EgressResult.self) { group in
                    var next = 0
                    let window = max(1, min(maxInFlight, resources.count))
                    // Prime the window, spacing launches so they don't hit as a burst.
                    while next < window {
                        let res = resources[next]; next += 1
                        group.addTask { await fetch(res, session: session) }
                        if next < window { try? await Task.sleep(nanoseconds: staggerMillis * 1_000_000) }
                    }
                    // Drain: each finished slot launches the next resource, holding the
                    // window at `maxInFlight` and naturally spacing the remaining starts.
                    while let r = await group.next() {
                        if Task.isCancelled { group.cancelAll(); break }
                        continuation.yield(r)
                        if next < resources.count {
                            let res = resources[next]; next += 1
                            group.addTask { await fetch(res, session: session) }
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    // MARK: - session

    static func makeSession(socksPort: Int, timeout: TimeInterval) -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        let port = NWEndpoint.Port(rawValue: UInt16(socksPort)) ?? .any
        let proxy = ProxyConfiguration(socksv5Proxy: .hostPort(host: "127.0.0.1", port: port))
        cfg.proxyConfigurations = [proxy]
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout + 4
        cfg.waitsForConnectivity = false
        cfg.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (compatible; CheckNet/1.0; +network-diagnostics)",
            "Accept": "application/json, text/plain, */*",
        ]
        return URLSession(configuration: cfg)
    }

    static func fetch(_ res: EgressResource, session: URLSession) async -> EgressResult {
        guard let url = URL(string: res.url) else {
            return EgressResult(name: res.name, category: res.category, url: res.url,
                                info: nil, error: "invalid address", millis: 0)
        }
        // Timed from here — the request's own round-trip, not the time it spent
        // waiting for a free slot in the window.
        let start = MonoClock.nanos()
        func done(_ info: EgressInfo?, _ error: String?) -> EgressResult {
            EgressResult(name: res.name, category: res.category, url: res.url,
                         info: info, error: error, millis: MonoClock.millisSince(start))
        }
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
                return done(nil, "HTTP \(http.statusCode)")
            }
            guard let info = parse(res.kind, data: data) else { return done(nil, "response not parsed") }
            return done(info, nil)
        } catch is CancellationError {
            return done(nil, "cancelled")
        } catch let error as URLError {
            return done(nil, reason(for: error))
        } catch {
            return done(nil, error.localizedDescription)
        }
    }

    /// Turn the noisiest URLErrors into a short operator-readable cause.
    static func reason(for error: URLError) -> String {
        switch error.code {
        case .timedOut: return "timeout"
        case .cannotConnectToHost, .cannotFindHost: return "proxy blocked it"
        case .secureConnectionFailed, .serverCertificateUntrusted: return "TLS error"
        case .notConnectedToInternet, .networkConnectionLost: return "connection lost"
        default: return "no response"
        }
    }

    // MARK: - parsing

    static func parse(_ kind: EgressResource.Kind, data: Data) -> EgressInfo? {
        switch kind {
        case .plain:
            let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return isIPAddress(s) ? EgressInfo(ip: s) : nil
        case .trace:
            return parseTrace(data)
        case let .json(ipKeys, countryKeys, asnKeys, orgKeys):
            return parseJSON(data, ip: ipKeys, country: countryKeys, asn: asnKeys, org: orgKeys)
        }
    }

    /// Cloudflare's `/cdn-cgi/trace` is `key=value` lines: `ip`, `loc` (country),
    /// `colo` (edge datacenter), `warp`.
    static func parseTrace(_ data: Data) -> EgressInfo? {
        var fields: [String: String] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let kv = line.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { fields[String(kv[0])] = String(kv[1]) }
        }
        guard let ip = fields["ip"], isIPAddress(ip) else { return nil }
        let colo = fields["colo"].map { "data center \($0)" }
        return EgressInfo(ip: ip, country: fields["loc"], note: colo)
    }

    static func parseJSON(_ data: Data, ip ipKeys: [String], country countryKeys: [String],
                          asn asnKeys: [String], org orgKeys: [String]) -> EgressInfo? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard let ip = firstString(root, ipKeys), isIPAddress(ip) else { return nil }
        return EgressInfo(
            ip: ip,
            country: firstString(root, countryKeys),
            asn: firstASN(root, asnKeys),
            org: firstString(root, orgKeys)
        )
    }

    /// Read a dotted key path (`connection.isp`) out of a decoded JSON object.
    static func value(_ root: Any, path: String) -> Any? {
        var current: Any? = root
        for part in path.split(separator: ".") {
            guard let dict = current as? [String: Any] else { return nil }
            current = dict[String(part)]
        }
        return current
    }

    static func firstString(_ root: Any, _ keys: [String]) -> String? {
        for key in keys {
            if let s = stringify(value(root, path: key)), !s.isEmpty { return s }
        }
        return nil
    }

    static func firstASN(_ root: Any, _ keys: [String]) -> String? {
        for key in keys {
            let raw = value(root, path: key)
            if let n = raw as? NSNumber, !(raw is String) { return "AS\(n.intValue)" }
            if let s = stringify(raw), !s.isEmpty {
                let trimmed = s.trimmingCharacters(in: .whitespaces)
                if trimmed.allSatisfy(\.isNumber) { return "AS\(trimmed)" }
                return trimmed
            }
        }
        return nil
    }

    static func stringify(_ any: Any?) -> String? {
        switch any {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    /// True for a syntactically valid IPv4 or IPv6 literal.
    static func isIPAddress(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 45 else { return false }
        var v4 = in_addr(); var v6 = in6_addr()
        return s.withCString { inet_pton(AF_INET, $0, &v4) == 1 || inet_pton(AF_INET6, $0, &v6) == 1 }
    }
}
