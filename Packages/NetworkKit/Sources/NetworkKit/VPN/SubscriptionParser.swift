import Foundation

/// One extra parameter carried by a link/config beyond the headline fields —
/// `fp`, `pbk`, `sid`, `alpn`, `mux`, `sockopt`, xhttp `extra`, `route`, …
public struct ProxyParam: Hashable, Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let value: String
    public init(key: String, value: String) { self.key = key; self.value = value }
}

/// One proxy node parsed out of a subscription.
public struct ProxyNode: Equatable, Hashable, Sendable, Identifiable {
    public enum Proto: String, Sendable {
        case vless, trojan, vmess, shadowsocks, hysteria2, tuic, unknown
    }
    public let id = UUID()
    public var name: String
    public var proto: Proto
    public var host: String
    public var port: Int
    public var security: String     // tls / reality / none
    public var sni: String
    public var network: String      // tcp / ws / grpc / h2 …
    public var flow: String
    /// uuid (vless/vmess) or password (trojan/ss) — needed to build a test config.
    public var credential: String = ""
    public var isReality: Bool { security.lowercased() == "reality" }
    /// Original share link or this node's config block, for copy / hand-off.
    public var raw: String
    /// Everything else the link/config carried, in source order.
    public var extras: [ProxyParam] = []
    /// The complete Xray config delivered for this host, when the subscription
    /// ships one config per server (Happ/Xray JSON arrays).
    public var fullConfig: String?
    /// Inner hosts when this entry bundles several proxies (a "multihost"
    /// config). Empty for a plain single-server host. These are *not* shown in
    /// the main list — the user expands this entry to see them.
    public var children: [ProxyNode] = []
    public var isMultihost: Bool { !children.isEmpty }

    public static func == (a: ProxyNode, b: ProxyNode) -> Bool {
        a.id == b.id
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public enum SubscriptionFormat: String, Sendable {
    case base64List, plainList, clash, singbox, xray, unknown
}

/// Pure parser: raw subscription text → detected format + proxy nodes.
/// Network fetching / Happ·Incy unwrapping happen at the call site.
public enum SubscriptionParser {
    public struct Result: Sendable, Equatable {
        public let format: SubscriptionFormat
        public let nodes: [ProxyNode]
    }

    public static func parse(_ raw: String) -> Result {
        let content = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return Result(format: .unknown, nodes: []) }

        if content.hasPrefix("{") || content.hasPrefix("[") {
            if let r = parseJSON(content) { return r }
        }
        if content.contains("proxies:") {
            return Result(format: .clash, nodes: parseClash(content))
        }
        if !content.contains("://"), let decoded = base64Text(content), decoded.contains("://") {
            return Result(format: .base64List, nodes: parseLinks(decoded))
        }
        if content.contains("://") {
            return Result(format: .plainList, nodes: parseLinks(content))
        }
        return Result(format: .unknown, nodes: [])
    }

    // MARK: - Share-link list

    private static func parseLinks(_ text: String) -> [ProxyNode] {
        text.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap(parseNode)
    }

    static func parseNode(_ link: String) -> ProxyNode? {
        let lower = link.lowercased()
        if lower.hasPrefix("vless://") { return parseURI(link, proto: .vless) }
        if lower.hasPrefix("trojan://") { return parseURI(link, proto: .trojan) }
        if lower.hasPrefix("vmess://") { return parseVMess(link) }
        if lower.hasPrefix("ss://") { return parseSS(link) }
        if lower.hasPrefix("hysteria2://") || lower.hasPrefix("hy2://") { return parseURI(link, proto: .hysteria2) }
        if lower.hasPrefix("tuic://") { return parseURI(link, proto: .tuic) }
        return nil
    }

    /// vless/trojan/hysteria2/tuic: `scheme://userinfo@host:port?query#name`
    private static func parseURI(_ link: String, proto: ProxyNode.Proto) -> ProxyNode? {
        guard let schemeRange = link.range(of: "://") else { return nil }
        var body = String(link[schemeRange.upperBound...])

        var name = ""
        if let h = body.firstIndex(of: "#") {
            name = String(body[body.index(after: h)...]).removingPercentEncoding ?? String(body[body.index(after: h)...])
            body = String(body[..<h])
        }
        var query = ""
        if let q = body.firstIndex(of: "?") {
            query = String(body[body.index(after: q)...])
            body = String(body[..<q])
        }
        var hostPort = body
        var credential = ""
        if let at = body.lastIndex(of: "@") {
            credential = String(body[..<at]).removingPercentEncoding ?? String(body[..<at])
            hostPort = String(body[body.index(after: at)...])
        }
        guard let (host, port) = splitHostPort(hostPort) else { return nil }

        let params = queryParams(query)
        let security = params["security"] ?? (proto == .trojan ? "tls" : "none")
        // Everything not already surfaced as a headline field — fp, pbk, sid,
        // spx, alpn, mux, encryption, path/host/mode, xhttp `extra`, `route`, …
        let shown: Set<String> = ["security", "sni", "peer", "type", "flow"]
        let extras = orderedQueryKeys(query)
            .filter { !shown.contains($0) }
            .compactMap { key in params[key].map { ProxyParam(key: key, value: $0) } }
        return ProxyNode(
            name: name.isEmpty ? host : name,
            proto: proto,
            host: host,
            port: port,
            security: security,
            sni: params["sni"] ?? params["peer"] ?? "",
            network: params["type"] ?? "tcp",
            flow: params["flow"] ?? "",
            credential: credential,
            raw: link,
            extras: extras
        )
    }

    /// vmess: `vmess://<base64 JSON>`
    private static func parseVMess(_ link: String) -> ProxyNode? {
        let b64 = String(link.dropFirst("vmess://".count))
        guard let data = base64Data(b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func s(_ k: String) -> String {
            if let v = obj[k] as? String { return v }
            if let n = obj[k] as? NSNumber { return n.stringValue }
            return ""
        }
        guard let port = Int(s("port")) else { return nil }
        let tls = s("tls")
        return ProxyNode(
            name: s("ps").isEmpty ? s("add") : s("ps"),
            proto: .vmess,
            host: s("add"),
            port: port,
            security: tls.isEmpty ? "none" : tls,
            sni: s("sni").isEmpty ? s("host") : s("sni"),
            network: s("net").isEmpty ? "tcp" : s("net"),
            flow: "",
            credential: s("id"),
            raw: link
        )
    }

    /// ss: SIP002 `ss://<base64(method:pass)>@host:port#name`
    /// or legacy `ss://<base64(method:pass@host:port)>#name`
    private static func parseSS(_ link: String) -> ProxyNode? {
        var body = String(link.dropFirst("ss://".count))
        var name = ""
        if let h = body.firstIndex(of: "#") {
            name = String(body[body.index(after: h)...]).removingPercentEncoding ?? ""
            body = String(body[..<h])
        }
        if let q = body.firstIndex(of: "?") { body = String(body[..<q]) }

        var hostPort: String?
        if let at = body.lastIndex(of: "@") {
            hostPort = String(body[body.index(after: at)...])
        } else if let decoded = base64Text(body), let at = decoded.lastIndex(of: "@") {
            hostPort = String(decoded[decoded.index(after: at)...])
        }
        guard let hp = hostPort, let (host, port) = splitHostPort(hp) else { return nil }
        return ProxyNode(
            name: name.isEmpty ? host : name,
            proto: .shadowsocks, host: host, port: port,
            security: "none", sni: "", network: "tcp", flow: "", raw: link
        )
    }

    // MARK: - JSON (sing-box + Xray/v2ray, object or array-of-configs)

    private static let proxyProtos: Set<String> =
        ["vless", "trojan", "vmess", "shadowsocks", "ss", "hysteria2", "tuic"]

    private static func parseJSON(_ text: String) -> Result? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return nil }

        // Xray / Happ subscription: an ARRAY of full configs, one per user-facing
        // host. Each config's `remarks` is its name; a config with several proxy
        // outbounds is a "multihost" the user can expand — one row, not many.
        if let arr = json as? [[String: Any]], arr.contains(where: { $0["outbounds"] != nil }) {
            let nodes = arr.compactMap(parseConfigHost)
            return Result(format: .xray, nodes: nodes)
        }

        guard let obj = json as? [String: Any],
              let obs = obj["outbounds"] as? [[String: Any]] else { return nil }

        // A single Xray config object = one host too; sing-box lists a host per
        // proxy outbound (that's what its clients show).
        if obs.contains(where: { $0["protocol"] != nil && $0["settings"] != nil }) {
            guard let host = parseConfigHost(obj) else { return nil }
            return Result(format: .xray, nodes: [host])
        }
        let nodes = obs.compactMap(parseSingBoxOutbound)
        return Result(format: .singbox, nodes: nodes)
    }

    /// Turn one full config into a single user-facing host: named by `remarks`,
    /// connection details from its primary proxy outbound, and inner hosts kept
    /// as `children` when it bundles more than one proxy.
    private static func parseConfigHost(_ config: [String: Any]) -> ProxyNode? {
        guard let obs = config["outbounds"] as? [[String: Any]] else { return nil }
        let proxies = obs.filter(isProxyOutbound)
        guard !proxies.isEmpty else { return nil }
        // The default route's outbound is the entry point (tagged "proxy").
        let primary = proxies.first { ($0["tag"] as? String) == "proxy" } ?? proxies[0]
        guard var node = parseAnyOutbound(primary) else { return nil }

        if let remark = config["remarks"] as? String, !remark.isEmpty { node.name = remark }
        node.fullConfig = prettyJSON(config)
        if proxies.count > 1 { node.children = proxies.compactMap(parseAnyOutbound) }
        return node
    }

    private static func isProxyOutbound(_ ob: [String: Any]) -> Bool {
        let proto = (ob["protocol"] as? String) ?? (ob["type"] as? String) ?? ""
        return proxyProtos.contains(proto)
    }

    private static func parseAnyOutbound(_ ob: [String: Any]) -> ProxyNode? {
        if ob["protocol"] != nil, ob["settings"] != nil { return parseXrayOutbound(ob) }
        return parseSingBoxOutbound(ob)
    }

    /// Flattens a config block into `dot.path → value` rows, skipping the fields
    /// already shown as headline properties. Nested objects/arrays that aren't
    /// plain scalars are rendered as compact JSON (xhttp `extra`, `sockopt`, …).
    static func flattenParams(_ obj: Any, prefix: String = "", skip: Set<String> = []) -> [ProxyParam] {
        var out: [ProxyParam] = []
        switch obj {
        case let dict as [String: Any]:
            for key in dict.keys.sorted() {
                let path = prefix.isEmpty ? key : "\(prefix).\(key)"
                guard !skip.contains(path) else { continue }
                out += flattenParams(dict[key] as Any, prefix: path, skip: skip)
            }
        case let arr as [Any]:
            if arr.isEmpty { break }
            // Scalar arrays (alpn, shortIds) read better on one line.
            if arr.allSatisfy({ !($0 is [String: Any]) && !($0 is [Any]) }) {
                out.append(ProxyParam(key: prefix, value: arr.map { scalarText($0) }.joined(separator: ", ")))
            } else {
                for (i, item) in arr.enumerated() {
                    out += flattenParams(item, prefix: "\(prefix)[\(i)]", skip: skip)
                }
            }
        default:
            let text = scalarText(obj)
            if !text.isEmpty { out.append(ProxyParam(key: prefix, value: text)) }
        }
        return out
    }

    private static func scalarText(_ any: Any) -> String {
        switch any {
        case let s as String: return s
        case let b as Bool: return b ? "true" : "false"
        case let n as NSNumber: return n.stringValue
        default: return String(describing: any)
        }
    }

    private static func parseSingBoxOutbound(_ ob: [String: Any]) -> ProxyNode? {
        guard let type = ob["type"] as? String, proxyProtos.contains(type),
              let server = ob["server"] as? String,
              let port = intVal(ob["server_port"]) else { return nil }
        let tls = ob["tls"] as? [String: Any]
        let enabled = (tls?["enabled"] as? Bool) ?? false
        let reality = (tls?["reality"] as? [String: Any])?["enabled"] as? Bool ?? false
        return ProxyNode(
            name: (ob["tag"] as? String) ?? server,
            proto: normalizeProto(type),
            host: server, port: port,
            security: reality ? "reality" : (enabled ? "tls" : "none"),
            sni: (tls?["server_name"] as? String) ?? "",
            network: (ob["network"] as? String) ?? "tcp",
            flow: (ob["flow"] as? String) ?? "",
            raw: prettyJSON(ob) ?? ((ob["tag"] as? String) ?? server),
            extras: flattenParams(ob, skip: [
                "type", "tag", "server", "server_port", "network", "flow",
                "tls.enabled", "tls.server_name", "tls.reality.enabled",
            ])
        )
    }

    private static func parseXrayOutbound(_ ob: [String: Any]) -> ProxyNode? {
        guard let proto = ob["protocol"] as? String, proxyProtos.contains(proto) else { return nil }
        let settings = ob["settings"] as? [String: Any]
        var host = "", port = 0, flow = ""
        if let vnext = (settings?["vnext"] as? [[String: Any]])?.first {
            host = vnext["address"] as? String ?? ""
            port = intVal(vnext["port"]) ?? 0
            if let user = (vnext["users"] as? [[String: Any]])?.first { flow = user["flow"] as? String ?? "" }
        } else if let server = (settings?["servers"] as? [[String: Any]])?.first {
            host = server["address"] as? String ?? ""
            port = intVal(server["port"]) ?? 0
        }
        guard !host.isEmpty, port > 0 else { return nil }

        let stream = ob["streamSettings"] as? [String: Any]
        let security = (stream?["security"] as? String) ?? "none"
        var sni = ""
        if security == "reality", let rs = stream?["realitySettings"] as? [String: Any] {
            sni = rs["serverName"] as? String ?? ""
        } else if let ts = stream?["tlsSettings"] as? [String: Any] {
            sni = ts["serverName"] as? String ?? ""
        }
        return ProxyNode(
            name: (ob["tag"] as? String) ?? host,
            proto: normalizeProto(proto),
            host: host, port: port,
            security: security,
            sni: sni,
            network: (stream?["network"] as? String) ?? "tcp",
            flow: flow,
            raw: prettyJSON(ob) ?? ((ob["tag"] as? String) ?? host),
            // fingerprint, publicKey/shortId, alpn, mux, sockopt, xhttp extra …
            extras: flattenParams(ob, skip: [
                "protocol", "tag",
                "streamSettings.network", "streamSettings.security",
                "streamSettings.realitySettings.serverName",
                "streamSettings.tlsSettings.serverName",
                "settings.vnext[0].address", "settings.vnext[0].port",
                "settings.servers[0].address", "settings.servers[0].port",
                "settings.vnext[0].users[0].flow",
            ])
        )
    }

    /// Pretty-printed JSON for a node's own config block — what the detail
    /// screen shows and copies.
    static func prettyJSON(_ obj: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj,
                                                     options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func intVal(_ any: Any?) -> Int? {
        if let n = any as? NSNumber { return n.intValue }
        if let i = any as? Int { return i }
        if let s = any as? String { return Int(s) }
        return nil
    }

    // MARK: - Clash (flow-style proxies only)

    private static func parseClash(_ text: String) -> [ProxyNode] {
        var nodes: [ProxyNode] = []
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard l.hasPrefix("- {"), l.contains("server:") else { continue }
            let fields = clashFields(l)
            guard let server = fields["server"], let portStr = fields["port"], let port = Int(portStr) else { continue }
            let type = fields["type"] ?? "unknown"
            let reality = l.contains("reality-opts") || fields["reality"] != nil
            nodes.append(ProxyNode(
                name: fields["name"] ?? server,
                proto: normalizeProto(type),
                host: server, port: port,
                security: reality ? "reality" : ((fields["tls"] == "true") ? "tls" : "none"),
                sni: fields["servername"] ?? fields["sni"] ?? "",
                network: fields["network"] ?? "tcp",
                flow: fields["flow"] ?? "",
                raw: l
            ))
        }
        return nodes
    }

    private static func clashFields(_ line: String) -> [String: String] {
        let inner = line.drop(while: { $0 != "{" }).dropFirst().reversed().drop(while: { $0 != "}" }).dropFirst().reversed()
        var out: [String: String] = [:]
        for pair in String(inner).split(separator: ",") {
            let kv = pair.split(separator: ":", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let k = kv[0].trimmingCharacters(in: .whitespaces).lowercased()
            var v = kv[1].trimmingCharacters(in: .whitespaces)
            v = v.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            out[k] = v
        }
        return out
    }

    // MARK: - helpers

    /// Normalise protocol names across schemes (`ss` ↔ `shadowsocks`, `hy2` …).
    static func normalizeProto(_ s: String) -> ProxyNode.Proto {
        switch s.lowercased() {
        case "ss", "shadowsocks": return .shadowsocks
        case "vless": return .vless
        case "vmess": return .vmess
        case "trojan": return .trojan
        case "hysteria2", "hy2": return .hysteria2
        case "tuic": return .tuic
        default: return .unknown
        }
    }

    static func splitHostPort(_ s: String) -> (String, Int)? {
        if s.hasPrefix("["), let close = s.firstIndex(of: "]") {   // IPv6
            let host = String(s[s.index(after: s.startIndex)..<close])
            let rest = s[s.index(after: close)...]
            guard rest.hasPrefix(":"), let port = Int(rest.dropFirst()) else { return nil }
            return (host, port)
        }
        guard let colon = s.lastIndex(of: ":"), let port = Int(s[s.index(after: colon)...]) else { return nil }
        return (String(s[..<colon]), port)
    }

    /// Query keys in the order the link wrote them, so the detail screen shows
    /// parameters the way the provider ordered them.
    private static func queryParams_order(_ query: String) -> [String] { orderedQueryKeys(query) }

    private static func orderedQueryKeys(_ query: String) -> [String] {
        var seen = Set<String>(), keys: [String] = []
        for pair in query.split(separator: "&") {
            guard let k = pair.split(separator: "=", maxSplits: 1).first else { continue }
            let key = String(k).lowercased()
            if seen.insert(key).inserted { keys.append(key) }
        }
        return keys
    }

    private static func queryParams(_ query: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            out[String(kv[0]).lowercased()] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
        }
        return out
    }

    private static func base64Data(_ text: String) -> Data? {
        var s = text.filter { !$0.isWhitespace }
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.hasSuffix("=") { s.removeLast() }
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        return Data(base64Encoded: s)
    }

    private static func base64Text(_ text: String) -> String? {
        base64Data(text).flatMap { String(data: $0, encoding: .utf8) }
    }
}
