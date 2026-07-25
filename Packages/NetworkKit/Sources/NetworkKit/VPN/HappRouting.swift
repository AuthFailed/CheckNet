import Foundation

/// A Happ routing profile — the JSON payload carried by a
/// `happ://routing/add/<base64(JSON)>` (or `…/onadd/…`) deep link.
///
/// Field names and value shapes mirror what the Happ clients read: booleans
/// travel as the strings `"true"`/`"false"`, `DnsHosts` is a JSON object, and
/// the site/IP buckets are string arrays whose entries are either `geosite:`/
/// `geoip:` tags, bare domains, or IP/CIDR. We decode into typed Swift and
/// re-encode back to the same wire shape.
public struct HappRoutingProfile: Equatable, Sendable {
    public var name: String
    public var globalProxy: Bool
    /// Priority of the buckets, e.g. `"block-proxy-direct"`.
    public var routeOrder: String
    // DNS — both the plain server (`RemoteDns`/`DomesticDns`) and the typed
    // transport (`…DNSType`/`…DNSDomain`/`…DNSIP`) travel in a real config.
    public var remoteDNS: String
    public var remoteDNSType: String        // DoH / DoU / DoT / DoQ
    public var remoteDNSDomain: String
    public var remoteDNSIP: String
    public var domesticDNS: String
    public var domesticDNSType: String
    public var domesticDNSDomain: String
    public var domesticDNSIP: String
    public var geoIPURL: String
    public var geoSiteURL: String
    /// Unix seconds, as a string, or empty.
    public var lastUpdated: String
    public var dnsHosts: [String: String]
    public var directSites: [String]
    public var directIP: [String]
    public var proxySites: [String]
    public var proxyIP: [String]
    public var blockSites: [String]
    public var blockIP: [String]
    public var domainStrategy: String       // IPIfNonMatch / IPOnDemand / AsIs
    public var fakeDNS: Bool
    public var useChunkFiles: Bool

    public init(
        name: String = "",
        globalProxy: Bool = false,
        routeOrder: String = "",
        remoteDNS: String = "",
        remoteDNSType: String = "DoH",
        remoteDNSDomain: String = "",
        remoteDNSIP: String = "",
        domesticDNS: String = "",
        domesticDNSType: String = "DoH",
        domesticDNSDomain: String = "",
        domesticDNSIP: String = "",
        geoIPURL: String = "",
        geoSiteURL: String = "",
        lastUpdated: String = "",
        dnsHosts: [String: String] = [:],
        directSites: [String] = [],
        directIP: [String] = [],
        proxySites: [String] = [],
        proxyIP: [String] = [],
        blockSites: [String] = [],
        blockIP: [String] = [],
        domainStrategy: String = "IPIfNonMatch",
        fakeDNS: Bool = false,
        useChunkFiles: Bool = false
    ) {
        self.name = name
        self.globalProxy = globalProxy
        self.routeOrder = routeOrder
        self.remoteDNS = remoteDNS
        self.remoteDNSType = remoteDNSType
        self.remoteDNSDomain = remoteDNSDomain
        self.remoteDNSIP = remoteDNSIP
        self.domesticDNS = domesticDNS
        self.domesticDNSType = domesticDNSType
        self.domesticDNSDomain = domesticDNSDomain
        self.domesticDNSIP = domesticDNSIP
        self.geoIPURL = geoIPURL
        self.geoSiteURL = geoSiteURL
        self.lastUpdated = lastUpdated
        self.dnsHosts = dnsHosts
        self.directSites = directSites
        self.directIP = directIP
        self.proxySites = proxySites
        self.proxyIP = proxyIP
        self.blockSites = blockSites
        self.blockIP = blockIP
        self.domainStrategy = domainStrategy
        self.fakeDNS = fakeDNS
        self.useChunkFiles = useChunkFiles
    }

    /// `LastUpdated` parsed from unix seconds, if present and numeric.
    public var lastUpdatedDate: Date? {
        guard let secs = TimeInterval(lastUpdated.trimmingCharacters(in: .whitespaces)),
              secs > 0 else { return nil }
        return Date(timeIntervalSince1970: secs)
    }

    /// Total rules across every bucket — a quick "how big is this profile".
    public var ruleCount: Int {
        directSites.count + directIP.count + proxySites.count + proxyIP.count
            + blockSites.count + blockIP.count
    }
}

/// What a single site/IP rule entry is, so the UI can label and group it.
public enum HappRuleEntry: Equatable, Sendable {
    case geositeTag(String)   // "geosite:youtube" → "youtube"
    case geoipTag(String)     // "geoip:ru" → "ru"
    case ipCIDR(String)       // 1.2.3.0/24 or a bare IP
    case domain(String)       // example.com
    case raw(String)          // anything else (regexp:, keyword:, etc.)

    /// The tag/value without its `geosite:`/`geoip:` prefix.
    public var value: String {
        switch self {
        case let .geositeTag(v), let .geoipTag(v), let .ipCIDR(v), let .domain(v), let .raw(v): v
        }
    }

    public static func classify(_ raw: String) -> HappRuleEntry {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if let tag = s.dropPrefixIfPresent("geosite:") { return .geositeTag(tag) }
        if let tag = s.dropPrefixIfPresent("geoip:") { return .geoipTag(tag) }
        if isIPOrCIDR(s) { return .ipCIDR(s) }
        if s.contains(".") && !s.contains(":") && !s.contains(" ") { return .domain(s) }
        return .raw(s)
    }

    private static func isIPOrCIDR(_ s: String) -> Bool {
        let host = s.split(separator: "/").first.map(String.init) ?? s
        var v4 = in_addr(); var v6 = in6_addr()
        return host.withCString { inet_pton(AF_INET, $0, &v4) == 1 || inet_pton(AF_INET6, $0, &v6) == 1 }
    }
}

private extension String {
    func dropPrefixIfPresent(_ p: String) -> String? {
        hasPrefix(p) ? String(dropFirst(p.count)) : nil
    }
}

/// Decoder/encoder for `happ://routing/{add,onadd}/…` deep links.
public enum HappRoutingLink {
    /// The verb used when we encode; both `add` and `onadd` decode.
    public static let prefix = "happ://routing/add/"
    private static let scheme = "happ://routing/"

    public enum DecodeError: Error, Equatable, Sendable {
        case notARoutingLink
        case invalidBase64
        case notAnObject
    }

    /// Parse a `happ://routing/{add,onadd}/<base64 JSON>` link (or a bare base64
    /// body) into a typed profile. Unknown fields are ignored; missing fields
    /// fall back to defaults so older links still decode.
    public static func decode(_ raw: String) throws -> HappRoutingProfile {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String
        if let range = trimmed.range(of: scheme) {
            // After the scheme comes the verb (add/onadd) then a slash then base64.
            let rest = trimmed[range.upperBound...]
            guard let slash = rest.firstIndex(of: "/") else { throw DecodeError.notARoutingLink }
            body = String(rest[rest.index(after: slash)...])
        } else if !trimmed.contains("://") {
            body = trimmed                       // tolerate a pasted base64 payload
        } else {
            throw DecodeError.notARoutingLink
        }

        guard let data = Self.base64Decode(body) else { throw DecodeError.invalidBase64 }
        let json = try? JSONSerialization.jsonObject(with: data)
        guard let obj = json as? [String: Any] else { throw DecodeError.notAnObject }

        return HappRoutingProfile(
            name: str(obj, "Name"),
            globalProxy: boolFlag(obj, "GlobalProxy"),
            routeOrder: str(obj, "RouteOrder"),
            remoteDNS: str(obj, "RemoteDns"),
            remoteDNSType: str(obj, "RemoteDNSType", default: "DoH"),
            remoteDNSDomain: str(obj, "RemoteDNSDomain"),
            remoteDNSIP: str(obj, "RemoteDNSIP"),
            domesticDNS: str(obj, "DomesticDns"),
            domesticDNSType: str(obj, "DomesticDNSType", default: "DoH"),
            domesticDNSDomain: str(obj, "DomesticDNSDomain"),
            domesticDNSIP: str(obj, "DomesticDNSIP"),
            geoIPURL: str(obj, "Geoipurl"),
            geoSiteURL: str(obj, "Geositeurl"),
            lastUpdated: str(obj, "LastUpdated"),
            dnsHosts: stringMap(obj, "DnsHosts"),
            directSites: stringArray(obj, "DirectSites"),
            directIP: stringArray(obj, "DirectIp"),
            proxySites: stringArray(obj, "ProxySites"),
            proxyIP: stringArray(obj, "ProxyIp"),
            blockSites: stringArray(obj, "BlockSites"),
            blockIP: stringArray(obj, "BlockIp"),
            domainStrategy: str(obj, "DomainStrategy", default: "IPIfNonMatch"),
            fakeDNS: boolFlag(obj, "FakeDNS"),
            useChunkFiles: boolFlag(obj, "UseChunkFiles")
        )
    }

    /// Serialise a profile back into a `happ://routing/add/…` link. Booleans are
    /// emitted as `"true"`/`"false"` strings to match the Happ wire format.
    public static func encode(_ p: HappRoutingProfile) throws -> String {
        var obj: [String: Any] = [
            "Name": p.name,
            "GlobalProxy": flag(p.globalProxy),
            "RemoteDNSType": p.remoteDNSType,
            "RemoteDNSDomain": p.remoteDNSDomain,
            "RemoteDNSIP": p.remoteDNSIP,
            "DomesticDNSType": p.domesticDNSType,
            "DomesticDNSDomain": p.domesticDNSDomain,
            "DomesticDNSIP": p.domesticDNSIP,
            "Geoipurl": p.geoIPURL,
            "Geositeurl": p.geoSiteURL,
            "LastUpdated": p.lastUpdated,
            "DnsHosts": p.dnsHosts,
            "DirectSites": p.directSites,
            "DirectIp": p.directIP,
            "ProxySites": p.proxySites,
            "ProxyIp": p.proxyIP,
            "BlockSites": p.blockSites,
            "BlockIp": p.blockIP,
            "DomainStrategy": p.domainStrategy,
            "FakeDNS": flag(p.fakeDNS),
        ]
        // Fields Happ includes when set; only emit when populated so a re-encoded
        // legacy link stays legacy.
        if !p.remoteDNS.isEmpty { obj["RemoteDns"] = p.remoteDNS }
        if !p.domesticDNS.isEmpty { obj["DomesticDns"] = p.domesticDNS }
        if !p.routeOrder.isEmpty { obj["RouteOrder"] = p.routeOrder }
        if p.useChunkFiles { obj["UseChunkFiles"] = flag(true) }

        let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        return prefix + data.base64EncodedString()
    }

    // MARK: - JSON field helpers

    private static func str(_ o: [String: Any], _ key: String, default def: String = "") -> String {
        (o[key] as? String) ?? def
    }

    /// Happ stores booleans as the strings "true"/"false"; tolerate a real bool too.
    private static func boolFlag(_ o: [String: Any], _ key: String) -> Bool {
        if let s = o[key] as? String { return s.lowercased() == "true" }
        if let b = o[key] as? Bool { return b }
        return false
    }

    private static func flag(_ b: Bool) -> String { b ? "true" : "false" }

    private static func stringArray(_ o: [String: Any], _ key: String) -> [String] {
        (o[key] as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private static func stringMap(_ o: [String: Any], _ key: String) -> [String: String] {
        guard let m = o[key] as? [String: Any] else { return [:] }
        return m.reduce(into: [:]) { acc, kv in
            if let v = kv.value as? String { acc[kv.key] = v }
        }
    }

    /// Standard or URL-safe base64, padding-tolerant.
    private static func base64Decode(_ text: String) -> Data? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let pad = (4 - s.count % 4) % 4
        s += String(repeating: "=", count: pad)
        return Data(base64Encoded: s)
    }
}
