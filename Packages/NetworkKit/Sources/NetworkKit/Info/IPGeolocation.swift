import Foundation

/// Where an IP address sits: country, city, the network (ASN/org) that announces
/// it, and — where the provider reports it — whether it's a hosting/VPN/proxy
/// address. Queries free, key-less HTTPS providers with a fallback chain, so one
/// being rate-limited or down doesn't sink the lookup.
///
/// This sends the queried IP to a third party, which is why the tool explains
/// itself through its ⓘ before it runs. Nothing else about the user is sent.
public struct IPGeolocation: Sendable {
    public init() {}

    /// Look up `query` — an IP literal, a hostname (resolved first), or empty for
    /// the caller's own public address.
    public func locate(query: String) async throws -> IPGeoResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let ip = try await Self.resolveTarget(trimmed)
        for provider in Self.providers {
            guard let url = provider.url(ip) else { continue }
            if let data = try? await Self.fetch(url), let result = provider.parse(data) {
                return result
            }
        }
        throw NetworkError.protocolError("Сервисы геолокации не ответили. Попробуйте позже.")
    }

    // MARK: Target resolution

    private static func resolveTarget(_ query: String) async throws -> String {
        if query.isEmpty { return try await ownIP() }
        // resolveFirst returns an IP literal unchanged and resolves a hostname.
        return try await HostResolver.resolveFirst(host: query).ipString
    }

    /// The caller's own public IP — ipquery.io returns it as bare text.
    static func ownIP() async throws -> String {
        guard let url = URL(string: "https://api.ipquery.io/") else {
            throw NetworkError.protocolError("bad url")
        }
        let data = try await fetch(url)
        let ip = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ip.isEmpty, ip.count <= 45 else {
            throw NetworkError.protocolError("не удалось определить свой IP")
        }
        return ip
    }

    private static func fetch(_ url: URL) async throws -> Data {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, _) = try await URLSession(configuration: cfg).data(from: url)
        return data
    }

    // MARK: Providers

    private struct Provider: Sendable {
        let url: @Sendable (String) -> URL?
        let parse: @Sendable (Data) -> IPGeoResult?
    }

    private static let providers: [Provider] = [
        Provider(url: { URL(string: "https://ipwho.is/\($0)") }, parse: parseIpwhois),
        Provider(url: { URL(string: "https://api.ipquery.io/\($0)") }, parse: parseIpquery)
    ]

    // MARK: Parsers (pure, testable)

    static func parseIpwhois(_ data: Data) -> IPGeoResult? {
        guard let r = try? JSONDecoder().decode(IpwhoisResponse.self, from: data), r.success == true,
              let ip = r.ip else { return nil }
        return IPGeoResult(
            ip: ip, country: r.country, countryCode: r.country_code, region: r.region, city: r.city,
            latitude: r.latitude, longitude: r.longitude,
            asn: r.connection?.asn.map { "AS\($0)" }, asnOrg: r.connection?.org, isp: r.connection?.isp,
            timezone: r.timezone?.id,
            isHosting: nil, isVPN: nil, isProxy: nil, isTor: nil,
            source: "ipwho.is"
        )
    }

    static func parseIpquery(_ data: Data) -> IPGeoResult? {
        guard let r = try? JSONDecoder().decode(IpqueryResponse.self, from: data), let ip = r.ip,
              // The bare-IP own-lookup path isn't JSON; a decoded object without a
              // location is a rate-limit/error body, not a real answer.
              r.location != nil || r.isp != nil else { return nil }
        return IPGeoResult(
            ip: ip, country: r.location?.country, countryCode: r.location?.country_code,
            region: r.location?.state, city: r.location?.city,
            latitude: r.location?.latitude, longitude: r.location?.longitude,
            asn: r.isp?.asn, asnOrg: r.isp?.org, isp: r.isp?.isp,
            timezone: r.location?.timezone,
            isHosting: r.risk?.is_datacenter, isVPN: r.risk?.is_vpn,
            isProxy: r.risk?.is_proxy, isTor: r.risk?.is_tor,
            source: "ipquery.io"
        )
    }

    // Provider response shapes.
    private struct IpwhoisResponse: Decodable {
        let ip: String?
        let success: Bool?
        let country: String?
        let country_code: String?
        let region: String?
        let city: String?
        let latitude: Double?
        let longitude: Double?
        let connection: Connection?
        let timezone: Timezone?
        struct Connection: Decodable { let asn: Int?; let org: String?; let isp: String? }
        struct Timezone: Decodable { let id: String? }
    }

    private struct IpqueryResponse: Decodable {
        let ip: String?
        let isp: ISP?
        let location: Location?
        let risk: Risk?
        struct ISP: Decodable { let asn: String?; let org: String?; let isp: String? }
        struct Location: Decodable {
            let country: String?
            let country_code: String?
            let city: String?
            let state: String?
            let latitude: Double?
            let longitude: Double?
            let timezone: String?
        }
        struct Risk: Decodable {
            let is_vpn: Bool?
            let is_tor: Bool?
            let is_proxy: Bool?
            let is_datacenter: Bool?
        }
    }
}

// MARK: - Result

public struct IPGeoResult: Sendable, Codable, Hashable {
    public let ip: String
    public let country: String?
    public let countryCode: String?
    public let region: String?
    public let city: String?
    public let latitude: Double?
    public let longitude: Double?
    /// "AS13335".
    public let asn: String?
    public let asnOrg: String?
    public let isp: String?
    public let timezone: String?
    public let isHosting: Bool?
    public let isVPN: Bool?
    public let isProxy: Bool?
    public let isTor: Bool?
    /// Which provider answered.
    public let source: String

    public init(ip: String, country: String?, countryCode: String?, region: String?, city: String?,
                latitude: Double?, longitude: Double?, asn: String?, asnOrg: String?, isp: String?,
                timezone: String?, isHosting: Bool?, isVPN: Bool?, isProxy: Bool?, isTor: Bool?,
                source: String) {
        self.ip = ip
        self.country = country
        self.countryCode = countryCode
        self.region = region
        self.city = city
        self.latitude = latitude
        self.longitude = longitude
        self.asn = asn
        self.asnOrg = asnOrg
        self.isp = isp
        self.timezone = timezone
        self.isHosting = isHosting
        self.isVPN = isVPN
        self.isProxy = isProxy
        self.isTor = isTor
        self.source = source
    }

    /// The AS number without the "AS" prefix, for building bgp.tools / he.net links.
    public var asNumber: String? {
        guard let asn else { return nil }
        let digits = asn.uppercased().replacingOccurrences(of: "AS", with: "")
        return digits.isEmpty ? nil : digits
    }

    /// Flag emoji from the ISO country code, derived locally so it's independent
    /// of whatever the provider does or doesn't send.
    public var flagEmoji: String? {
        guard let cc = countryCode?.uppercased(), cc.count == 2, cc.allSatisfy(\.isLetter) else { return nil }
        var result = ""
        for scalar in cc.unicodeScalars {
            guard let flagScalar = UnicodeScalar(0x1F1E6 + scalar.value - 65) else { return nil }
            result.unicodeScalars.append(flagScalar)
        }
        return result
    }
}
