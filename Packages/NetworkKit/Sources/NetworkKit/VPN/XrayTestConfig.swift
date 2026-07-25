import Foundation

/// Builds a minimal Xray config for a **through-proxy reachability test**: one
/// local SOCKS inbound on `127.0.0.1:<port>` and a single proxy outbound for the
/// node, with routing/dns stripped so every request goes through the proxy.
///
/// When the node came from an Xray-JSON subscription we reuse its real outbound
/// verbatim (all Reality/flow/params already correct); otherwise we build one
/// from the parsed link fields.
public enum XrayTestConfig {
    public enum BuildError: Error, Equatable, Sendable { case noProxyOutbound, unsupported }

    public static func build(for node: ProxyNode, socksPort: Int) throws -> String {
        let outbound = try proxyOutbound(for: node)
        let config: [String: Any] = [
            "log": ["loglevel": "warning"],
            "inbounds": [[
                "tag": "socks", "listen": "127.0.0.1", "port": socksPort,
                "protocol": "socks", "settings": ["udp": false],
            ]],
            "outbounds": [outbound],
        ]
        let data = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// The proxy outbound dictionary for this node.
    static func proxyOutbound(for node: ProxyNode) throws -> [String: Any] {
        // Prefer the real config Xray shipped for this host.
        if let full = node.fullConfig,
           let data = full.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let outbounds = obj["outbounds"] as? [[String: Any]],
           var proxy = outbounds.first(where: { proxyProtocols.contains(($0["protocol"] as? String) ?? "") }) {
            proxy["tag"] = "proxy"
            return proxy
        }
        return try buildOutbound(from: node)
    }

    private static let proxyProtocols: Set<String> = ["vless", "vmess", "trojan", "shadowsocks"]

    /// Reconstruct an Xray outbound from a parsed link (vless / trojan).
    private static func buildOutbound(from node: ProxyNode) throws -> [String: Any] {
        let e = Dictionary(uniqueKeysWithValues: node.extras.map { ($0.key, $0.value) })
        var stream: [String: Any] = ["network": node.network]
        let security = node.security == "none" ? "none" : node.security
        stream["security"] = security
        if security == "reality" {
            var r: [String: Any] = ["serverName": node.sni]
            if let v = e["fp"] { r["fingerprint"] = v }
            if let v = e["pbk"] { r["publicKey"] = v }
            if let v = e["sid"] { r["shortId"] = v }
            r["spiderX"] = e["spx"] ?? "/"
            stream["realitySettings"] = r
        } else if security == "tls" {
            var t: [String: Any] = ["serverName": node.sni]
            if let v = e["fp"] { t["fingerprint"] = v }
            if let v = e["alpn"] { t["alpn"] = v.split(separator: ",").map(String.init) }
            stream["tlsSettings"] = t
        }

        switch node.proto {
        case .vless:
            var user: [String: Any] = ["id": node.credential, "encryption": e["encryption"] ?? "none"]
            if !node.flow.isEmpty { user["flow"] = node.flow }
            return [
                "protocol": "vless", "tag": "proxy",
                "settings": ["vnext": [["address": node.host, "port": node.port, "users": [user]]]],
                "streamSettings": stream,
            ]
        case .trojan:
            return [
                "protocol": "trojan", "tag": "proxy",
                "settings": ["servers": [["address": node.host, "port": node.port, "password": node.credential]]],
                "streamSettings": stream,
            ]
        default:
            throw BuildError.unsupported
        }
    }
}
