import Foundation

/// Where an IP address sits — country, city, the network (ASN/org), and whether
/// it looks like hosting/VPN/proxy. Queries several free, key-less providers
/// *at once* and reconciles them: the consensus is what most sources agree on,
/// and every source's own answer is kept so the caller can show the breakdown
/// and spot disagreements.
///
/// This sends the queried IP to third parties, which is why the tool explains
/// itself through its ⓘ before it runs. Nothing else about the user is sent.
public struct IPGeolocation: Sendable {
    public init() {}

    /// Look up `query` across every provider — an IP literal, a hostname
    /// (resolved first), or empty for the caller's own public address.
    static let maxmindSource = "MaxMind GeoLite2"

    public func lookup(query: String) async throws -> IPGeoLookup {
        let ip = try await Self.resolveTarget(query)
        // Refresh the offline database in the background; this run uses whatever
        // is already cached and MaxMind joins the results once it's present.
        Task.detached(priority: .utility) { await GeoLiteDatabase.shared.ensureFresh() }

        let collected = await withTaskGroup(of: IPGeoResult?.self) { group -> [IPGeoResult] in
            for provider in Self.providers {
                group.addTask { await provider.fetch(ip) }
            }
            group.addTask { await Self.maxmindLookup(ip) }   // offline, cached DB
            var out: [IPGeoResult] = []
            for await result in group { if let result { out.append(result) } }
            return out
        }
        guard !collected.isEmpty else {
            throw NetworkError.protocolError("Сервисы геолокации не ответили. Попробуйте позже.")
        }
        // Stable order: API providers as declared, then MaxMind.
        var ordered = Self.providers.compactMap { p in collected.first { $0.source == p.name } }
        if let maxmind = collected.first(where: { $0.source == Self.maxmindSource }) { ordered.append(maxmind) }
        return IPGeoLookup(ip: ip, providers: ordered, consensus: Self.consolidate(ordered, ip: ip))
    }

    // MARK: MaxMind GeoLite2 (offline)

    static func maxmindLookup(_ ip: String) async -> IPGeoResult? {
        let db = GeoLiteDatabase.shared
        guard let cityReader = await db.reader(.city), let city = cityReader.lookup(ip: ip) else { return nil }
        let country = localizedName(city["country"]?["names"])
        let asnData = await db.reader(.asn)?.lookup(ip: ip)
        var asn: String?
        if let number = asnData?["autonomous_system_number"]?.uintValue { asn = "AS\(number)" }
        guard country != nil || asn != nil else { return nil }
        return IPGeoResult(
            ip: ip,
            country: country,
            countryCode: city["country"]?["iso_code"]?.stringValue,
            region: localizedName(city["subdivisions"]?.arrayValue?.first?["names"]),
            city: localizedName(city["city"]?["names"]),
            latitude: city["location"]?["latitude"]?.doubleValue,
            longitude: city["location"]?["longitude"]?.doubleValue,
            asn: asn, asnOrg: asnData?["autonomous_system_organization"]?.stringValue, isp: nil,
            timezone: city["location"]?["time_zone"]?.stringValue,
            isHosting: nil, isVPN: nil, isProxy: nil, isTor: nil, source: maxmindSource
        )
    }

    /// A GeoLite `names` map is keyed by language; prefer Russian, fall back to English.
    private static func localizedName(_ value: MMDBReader.Value?) -> String? {
        value?["ru"]?.stringValue ?? value?["en"]?.stringValue
    }

    // MARK: Consensus (pure)

    static func consolidate(_ results: [IPGeoResult], ip: String) -> IPGeoConsensus {
        // Most common non-nil value; ties broken toward the earlier provider.
        func majority<T: Hashable>(_ select: (IPGeoResult) -> T?) -> T? {
            var counts: [T: Int] = [:]
            var order: [T] = []
            for r in results {
                guard let value = select(r) else { continue }
                if counts[value] == nil { order.append(value) }
                counts[value, default: 0] += 1
            }
            var best: T?
            var bestCount = 0
            for value in order where counts[value]! > bestCount {
                best = value; bestCount = counts[value]!
            }
            return best
        }
        func median(_ select: (IPGeoResult) -> Double?) -> Double? {
            let values = results.compactMap(select).sorted()
            guard !values.isEmpty else { return nil }
            return values[values.count / 2]
        }
        func anyTrue(_ select: (IPGeoResult) -> Bool?) -> Bool? {
            let values = results.compactMap(select)
            return values.isEmpty ? nil : values.contains(true)
        }
        return IPGeoConsensus(
            ip: ip,
            country: majority { $0.country },
            countryCode: majority { $0.countryCode },
            region: majority { $0.region },
            city: majority { $0.city },
            latitude: median { $0.latitude },
            longitude: median { $0.longitude },
            asn: majority { $0.asn },
            asnOrg: majority { $0.asnOrg },
            timezone: majority { $0.timezone },
            isHosting: anyTrue { $0.isHosting },
            isVPN: anyTrue { $0.isVPN },
            isProxy: anyTrue { $0.isProxy },
            isTor: anyTrue { $0.isTor },
            sourceCount: results.count
        )
    }

    // MARK: Target resolution

    private static func resolveTarget(_ query: String) async throws -> String {
        if query.isEmpty { return try await ownIP() }
        return try await HostResolver.resolveFirst(host: query).ipString
    }

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
        let name: String
        let url: @Sendable (String) -> URL?
        let parse: @Sendable (Data) -> IPGeoResult?

        func fetch(_ ip: String) async -> IPGeoResult? {
            guard let url = url(ip), let data = try? await IPGeolocation.fetch(url) else { return nil }
            return parse(data)
        }
    }

    private static let providers: [Provider] = [
        // ip-api.com's free tier is HTTP-only; the app allows it via a scoped ATS
        // exception (only a public IP is ever sent).
        Provider(name: "ip-api.com",
                 url: { URL(string: "http://ip-api.com/json/\($0)?fields=status,country,countryCode,regionName,city,lat,lon,timezone,isp,org,as,asname,hosting,proxy,mobile,query") },
                 parse: parseIpapi),
        Provider(name: "ipwho.is", url: { URL(string: "https://ipwho.is/\($0)") }, parse: parseIpwhois),
        Provider(name: "ipquery.io", url: { URL(string: "https://api.ipquery.io/\($0)") }, parse: parseIpquery),
        Provider(name: "DB-IP", url: { URL(string: "https://api.db-ip.com/v2/free/\($0)") }, parse: parseDbip),
        Provider(name: "freeipapi.com", url: { URL(string: "https://freeipapi.com/api/json/\($0)") }, parse: parseFreeipapi)
    ]

    // MARK: Parsers (pure, testable)

    static func parseIpapi(_ data: Data) -> IPGeoResult? {
        guard let r = try? JSONDecoder().decode(IpapiResponse.self, from: data),
              r.status == "success", let ip = r.query else { return nil }
        // "as" is "AS15169 Google LLC": the number, then the org.
        var asn: String?
        var asnOrg: String? = r.org
        if let field = r.as, !field.isEmpty {
            let parts = field.split(separator: " ", maxSplits: 1)
            asn = parts.first.map(String.init)
            if parts.count > 1 { asnOrg = String(parts[1]) }
        }
        return IPGeoResult(
            ip: ip, country: r.country, countryCode: r.countryCode, region: r.regionName, city: r.city,
            latitude: r.lat, longitude: r.lon, asn: asn, asnOrg: asnOrg ?? r.asname, isp: r.isp,
            timezone: r.timezone, isHosting: r.hosting, isVPN: nil, isProxy: r.proxy, isTor: nil,
            source: "ip-api.com"
        )
    }

    static func parseIpwhois(_ data: Data) -> IPGeoResult? {
        guard let r = try? JSONDecoder().decode(IpwhoisResponse.self, from: data), r.success == true,
              let ip = r.ip else { return nil }
        return IPGeoResult(
            ip: ip, country: r.country, countryCode: r.country_code, region: r.region, city: r.city,
            latitude: r.latitude, longitude: r.longitude,
            asn: r.connection?.asn.map { "AS\($0)" }, asnOrg: r.connection?.org, isp: r.connection?.isp,
            timezone: r.timezone?.id, isHosting: nil, isVPN: nil, isProxy: nil, isTor: nil,
            source: "ipwho.is"
        )
    }

    static func parseIpquery(_ data: Data) -> IPGeoResult? {
        guard let r = try? JSONDecoder().decode(IpqueryResponse.self, from: data), let ip = r.ip,
              r.location != nil || r.isp != nil else { return nil }
        return IPGeoResult(
            ip: ip, country: r.location?.country, countryCode: r.location?.country_code,
            region: r.location?.state, city: r.location?.city,
            latitude: r.location?.latitude, longitude: r.location?.longitude,
            asn: r.isp?.asn, asnOrg: r.isp?.org, isp: r.isp?.isp, timezone: r.location?.timezone,
            isHosting: r.risk?.is_datacenter, isVPN: r.risk?.is_vpn,
            isProxy: r.risk?.is_proxy, isTor: r.risk?.is_tor, source: "ipquery.io"
        )
    }

    static func parseDbip(_ data: Data) -> IPGeoResult? {
        guard let r = try? JSONDecoder().decode(DbipResponse.self, from: data),
              let ip = r.ipAddress, r.countryName != nil else { return nil }
        return IPGeoResult(
            ip: ip, country: r.countryName, countryCode: r.countryCode, region: r.stateProv, city: r.city,
            latitude: nil, longitude: nil, asn: nil, asnOrg: nil, isp: nil, timezone: nil,
            isHosting: nil, isVPN: nil, isProxy: nil, isTor: nil, source: "DB-IP"
        )
    }

    static func parseFreeipapi(_ data: Data) -> IPGeoResult? {
        guard let r = try? JSONDecoder().decode(FreeipapiResponse.self, from: data),
              let ip = r.ipAddress, r.countryName != nil else { return nil }
        let asn: String? = r.asn.flatMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed != "0" else { return nil }
            return trimmed.uppercased().hasPrefix("AS") ? trimmed.uppercased() : "AS\(trimmed)"
        }
        return IPGeoResult(
            ip: ip, country: r.countryName, countryCode: r.countryCode, region: r.regionName,
            city: r.cityName, latitude: r.latitude, longitude: r.longitude,
            asn: asn, asnOrg: r.asnOrganization, isp: nil, timezone: r.timeZones?.first,
            isHosting: nil, isVPN: nil, isProxy: nil, isTor: nil, source: "freeipapi.com"
        )
    }

    // MARK: Response shapes

    private struct IpapiResponse: Decodable {
        let status: String?
        let query: String?
        let country: String?
        let countryCode: String?
        let regionName: String?
        let city: String?
        let lat: Double?
        let lon: Double?
        let timezone: String?
        let isp: String?
        let org: String?
        let `as`: String?
        let asname: String?
        let hosting: Bool?
        let proxy: Bool?
        let mobile: Bool?
    }

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

    private struct DbipResponse: Decodable {
        let ipAddress: String?
        let countryName: String?
        let countryCode: String?
        let city: String?
        let stateProv: String?
    }

    private struct FreeipapiResponse: Decodable {
        let ipAddress: String?
        let countryName: String?
        let countryCode: String?
        let cityName: String?
        let regionName: String?
        let latitude: Double?
        let longitude: Double?
        let asn: String?
        let asnOrganization: String?
        let timeZones: [String]?
    }
}

// MARK: - Per-provider result

public struct IPGeoResult: Sendable, Codable, Hashable, Identifiable {
    public var id: String { source }
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

    public var flagEmoji: String? { IPGeo.flag(countryCode) }
    public var asNumber: String? { IPGeo.asNumber(asn) }
}

// MARK: - Consensus + lookup

public struct IPGeoConsensus: Sendable, Codable, Hashable {
    public let ip: String
    public let country: String?
    public let countryCode: String?
    public let region: String?
    public let city: String?
    public let latitude: Double?
    public let longitude: Double?
    public let asn: String?
    public let asnOrg: String?
    public let timezone: String?
    public let isHosting: Bool?
    public let isVPN: Bool?
    public let isProxy: Bool?
    public let isTor: Bool?
    /// How many providers answered.
    public let sourceCount: Int

    public var flagEmoji: String? { IPGeo.flag(countryCode) }
    public var asNumber: String? { IPGeo.asNumber(asn) }
}

public struct IPGeoLookup: Sendable, Hashable {
    public let ip: String
    /// Every provider that answered, in a stable order.
    public let providers: [IPGeoResult]
    public let consensus: IPGeoConsensus
}

/// Small shared derivations, so the per-provider result and the consensus format
/// flags and AS numbers the same way.
enum IPGeo {
    static func flag(_ countryCode: String?) -> String? {
        guard let cc = countryCode?.uppercased(), cc.count == 2, cc.allSatisfy(\.isLetter) else { return nil }
        var result = ""
        for scalar in cc.unicodeScalars {
            guard let flagScalar = UnicodeScalar(0x1F1E6 + scalar.value - 65) else { return nil }
            result.unicodeScalars.append(flagScalar)
        }
        return result
    }

    static func asNumber(_ asn: String?) -> String? {
        guard let asn else { return nil }
        let digits = asn.uppercased().replacingOccurrences(of: "AS", with: "")
        return digits.isEmpty ? nil : digits
    }
}
