import Foundation

/// DNS resource record types supported by the client.
public enum DNSRecordType: UInt16, Sendable, CaseIterable, Codable {
    case a = 1
    case ns = 2
    case cname = 5
    case soa = 6
    case ptr = 12
    case mx = 15
    case txt = 16
    case aaaa = 28
    case srv = 33
    case caa = 257
    case https = 65

    public var label: String {
        switch self {
        case .a: return "A"
        case .ns: return "NS"
        case .cname: return "CNAME"
        case .soa: return "SOA"
        case .ptr: return "PTR"
        case .mx: return "MX"
        case .txt: return "TXT"
        case .aaaa: return "AAAA"
        case .srv: return "SRV"
        case .caa: return "CAA"
        case .https: return "HTTPS"
        }
    }
}

/// DNS response codes (RCODE).
public enum DNSResponseCode: Int, Sendable, Codable {
    case noError = 0
    case formErr = 1
    case servFail = 2
    case nxDomain = 3
    case notImp = 4
    case refused = 5
    case other = -1

    public init(rawCode: Int) { self = DNSResponseCode(rawValue: rawCode) ?? .other }

    public var label: String {
        switch self {
        case .noError: return "NOERROR"
        case .formErr: return "FORMERR"
        case .servFail: return "SERVFAIL"
        case .nxDomain: return "NXDOMAIN"
        case .notImp: return "NOTIMP"
        case .refused: return "REFUSED"
        case .other: return "OTHER"
        }
    }
}

/// A single decoded resource record.
public struct DNSRecord: Sendable, Hashable, Codable {
    public let name: String
    public let type: DNSRecordType?
    public let rawType: UInt16
    public let ttl: UInt32
    /// Human-readable value (IP, hostname, "10 mail.example.com", quoted TXT, etc.).
    public let value: String

    public init(name: String, type: DNSRecordType?, rawType: UInt16, ttl: UInt32, value: String) {
        self.name = name
        self.type = type
        self.rawType = rawType
        self.ttl = ttl
        self.value = value
    }
}

/// The result of a single DNS query against one resolver.
public struct DNSResult: Sendable, Hashable, Codable {
    public let resolver: String
    public let queryName: String
    public let queryType: DNSRecordType
    public let responseCode: DNSResponseCode
    public let answers: [DNSRecord]
    public let authorities: [DNSRecord]
    public let additionals: [DNSRecord]
    /// Round-trip latency in milliseconds.
    public let latencyMillis: Double
    public let authenticated: Bool  // AD bit (DNSSEC validated by resolver)
    public let truncated: Bool

    public init(resolver: String, queryName: String, queryType: DNSRecordType,
                responseCode: DNSResponseCode, answers: [DNSRecord],
                authorities: [DNSRecord] = [], additionals: [DNSRecord] = [],
                latencyMillis: Double, authenticated: Bool = false, truncated: Bool = false) {
        self.resolver = resolver
        self.queryName = queryName
        self.queryType = queryType
        self.responseCode = responseCode
        self.answers = answers
        self.authorities = authorities
        self.additionals = additionals
        self.latencyMillis = latencyMillis
        self.authenticated = authenticated
        self.truncated = truncated
    }

    /// Just the answer values of the queried type, sorted — useful for comparing resolvers.
    public var normalizedAnswerSet: Set<String> {
        Set(answers.filter { $0.rawType == queryType.rawValue }.map { $0.value.lowercased() })
    }
}

/// A well-known public resolver.
public struct DNSResolverInfo: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let name: String
    public let address: String
    public init(name: String, address: String) {
        self.id = address
        self.name = name
        self.address = address
    }

    public static let presets: [DNSResolverInfo] = [
        .init(name: "Cloudflare", address: "1.1.1.1"),
        .init(name: "Google", address: "8.8.8.8"),
        .init(name: "Quad9", address: "9.9.9.9"),
        .init(name: "OpenDNS", address: "208.67.222.222"),
        .init(name: "AdGuard", address: "94.140.14.14")
    ]
}
