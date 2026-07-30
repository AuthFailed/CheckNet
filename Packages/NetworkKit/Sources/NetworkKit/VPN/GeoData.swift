import Foundation

/// Minimal protobuf wire-format reader — just enough to walk the v2fly
/// `geosite.dat` / `geoip.dat` messages without pulling in a protobuf runtime.
/// Mirrors the hand-written DER/MMDB parsers already in the package.
struct ProtoReader {
    let bytes: [UInt8]
    var pos: Int
    let end: Int

    init(_ bytes: [UInt8], from: Int = 0, to: Int? = nil) {
        self.bytes = bytes; self.pos = from; self.end = to ?? bytes.count
    }

    var isAtEnd: Bool { pos >= end }

    mutating func readVarint() -> UInt64? {
        var result: UInt64 = 0, shift: UInt64 = 0
        while pos < end {
            let b = bytes[pos]; pos += 1
            result |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 { return result }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }

    /// Field number + wire type from the next tag.
    mutating func readTag() -> (field: Int, wire: Int)? {
        guard let v = readVarint() else { return nil }
        return (Int(v >> 3), Int(v & 0x7))
    }

    /// A length-delimited field's byte range `[start, end)`.
    mutating func readLengthDelimited() -> Range<Int>? {
        guard let len = readVarint() else { return nil }
        let start = pos, stop = pos + Int(len)
        guard stop <= end, stop >= start else { return nil }
        pos = stop
        return start..<stop
    }

    /// Advances past a field of the given wire type.
    mutating func skip(wire: Int) {
        switch wire {
        case 0: _ = readVarint()
        case 1: pos += 8
        case 2: _ = readLengthDelimited()
        case 5: pos += 4
        default: pos = end
        }
    }
}

public enum GeoDataKind: String, Sendable, Codable {
    case geosite, geoip
}

/// A category in a geo file (`country_code`), with how many rules it holds and
/// where its body lives in the source bytes (parsed on demand).
public struct GeoCategory: Sendable, Hashable, Codable, Identifiable {
    public var id: String { code }
    public let code: String
    public let count: Int
    let lower: Int
    let upper: Int
}

/// A geosite domain rule.
public struct GeoDomain: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: Int, Sendable, Codable {
        case plain = 0    // keyword / substring
        case regex = 1
        case domain = 2   // domain and its subdomains
        case full = 3     // exact match

        public var label: String {
            switch self {
            case .plain: "keyword"
            case .regex: "regexp"
            case .domain: "domain"
            case .full: "full"
            }
        }
    }
    public var id: String { "\(kind.rawValue):\(value)" }
    public let kind: Kind
    public let value: String
    /// Attribute tags like `@ads`, `@cn` attached to the rule.
    public let attributes: [String]
}

/// A geoip CIDR rule.
public struct GeoCIDR: Sendable, Hashable, Codable, Identifiable {
    public var id: String { "\(ip)/\(prefix)" }
    public let ip: String
    public let prefix: Int
    public var text: String { "\(ip)/\(prefix)" }
}

/// A parsed `geosite.dat` / `geoip.dat`. Holds the raw bytes and a category
/// index; individual rules are decoded on demand so a multi-megabyte file with
/// hundreds of thousands of rules never all sits in Swift objects at once.
public final class GeoDataDocument: Sendable {
    public let kind: GeoDataKind
    public let categories: [GeoCategory]
    private let data: [UInt8]

    init(kind: GeoDataKind, data: [UInt8], categories: [GeoCategory]) {
        self.kind = kind; self.data = data; self.categories = categories
    }

    public var totalRules: Int { categories.reduce(0) { $0 + $1.count } }

    /// Parses a geo file, auto-detecting geosite vs geoip when `kind` is nil.
    public static func load(_ raw: Data, kind forced: GeoDataKind? = nil) -> GeoDataDocument? {
        let bytes = [UInt8](raw)
        guard !bytes.isEmpty else { return nil }
        let kind = forced ?? detectKind(bytes)
        let cats = parseIndex(bytes)
        guard !cats.isEmpty else { return nil }
        return GeoDataDocument(kind: kind, data: bytes, categories: cats)
    }

    // MARK: - On-demand decoding

    public func domains(in category: GeoCategory) -> [GeoDomain] {
        var out: [GeoDomain] = []
        var r = ProtoReader(data, from: category.lower, to: category.upper)
        while !r.isAtEnd {
            guard let tag = r.readTag() else { break }
            if tag.field == 2, tag.wire == 2, let range = r.readLengthDelimited() {
                out.append(Self.parseDomain(data, range))
            } else { r.skip(wire: tag.wire) }
        }
        return out
    }

    public func cidrs(in category: GeoCategory) -> [GeoCIDR] {
        var out: [GeoCIDR] = []
        var r = ProtoReader(data, from: category.lower, to: category.upper)
        while !r.isAtEnd {
            guard let tag = r.readTag() else { break }
            if tag.field == 2, tag.wire == 2, let range = r.readLengthDelimited() {
                if let c = Self.parseCIDR(data, range) { out.append(c) }
            } else { r.skip(wire: tag.wire) }
        }
        return out
    }

    /// geosite: the category codes whose rules match `domain` (exact/subdomain/keyword).
    public func categoriesContaining(domain: String) -> [String] {
        let needle = domain.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        return categories.filter { cat in
            domains(in: cat).contains { Self.matches(needle, rule: $0) }
        }.map(\.code)
    }

    /// geoip: the category codes whose CIDRs contain `ip` (IPv4 only).
    public func categoriesContaining(ip: String) -> [String] {
        guard let q = IPv4Range.toUInt32(ip.trimmingCharacters(in: .whitespaces)) else { return [] }
        return categories.filter { cat in
            cidrs(in: cat).contains { c in
                guard c.prefix <= 32, let base = IPv4Range.toUInt32(c.ip) else { return false }
                let mask: UInt32 = c.prefix == 0 ? 0 : ~UInt32(0) << (32 - c.prefix)
                return (q & mask) == (base & mask)
            }
        }.map(\.code)
    }

    static func matches(_ host: String, rule: GeoDomain) -> Bool {
        let v = rule.value.lowercased()
        switch rule.kind {
        case .full:   return host == v
        case .domain: return host == v || host.hasSuffix("." + v)
        case .plain:  return host.contains(v)
        case .regex:  return (try? NSRegularExpression(pattern: rule.value))
            .map { $0.firstMatch(in: host, range: NSRange(host.startIndex..., in: host)) != nil } ?? false
        }
    }

    // MARK: - Parsing

    static func detectKind(_ bytes: [UInt8]) -> GeoDataKind {
        // First entry → first repeated inner message. In a geosite Domain the
        // first field (type) is a varint (wire 0); in a geoip CIDR the first
        // field (ip) is length-delimited bytes (wire 2). That tells them apart.
        var r = ProtoReader(bytes)
        guard let tag = r.readTag(), tag.field == 1, tag.wire == 2,
              let entry = r.readLengthDelimited() else { return .geosite }
        var e = ProtoReader(bytes, from: entry.lowerBound, to: entry.upperBound)
        while !e.isAtEnd {
            guard let t = e.readTag() else { break }
            if t.field == 2, t.wire == 2, let inner = e.readLengthDelimited() {
                var i = ProtoReader(bytes, from: inner.lowerBound, to: inner.upperBound)
                if let it = i.readTag(), it.field == 1 {
                    return it.wire == 2 ? .geoip : .geosite
                }
                return .geosite
            } else { e.skip(wire: t.wire) }
        }
        return .geosite
    }

    static func parseIndex(_ bytes: [UInt8]) -> [GeoCategory] {
        var out: [GeoCategory] = []
        var r = ProtoReader(bytes)
        while !r.isAtEnd {
            guard let tag = r.readTag() else { break }
            if tag.field == 1, tag.wire == 2, let entry = r.readLengthDelimited() {
                out.append(parseCategoryHeader(bytes, entry))
            } else { r.skip(wire: tag.wire) }
        }
        return out.filter { !$0.code.isEmpty }
    }

    static func parseCategoryHeader(_ bytes: [UInt8], _ range: Range<Int>) -> GeoCategory {
        var code = "", count = 0
        var r = ProtoReader(bytes, from: range.lowerBound, to: range.upperBound)
        while !r.isAtEnd {
            guard let tag = r.readTag() else { break }
            if tag.field == 1, tag.wire == 2, let s = r.readLengthDelimited() {
                code = String(decoding: bytes[s], as: UTF8.self)
            } else if tag.field == 2, tag.wire == 2 {
                count += 1
                _ = r.readLengthDelimited()
            } else { r.skip(wire: tag.wire) }
        }
        return GeoCategory(code: code.uppercased(), count: count,
                           lower: range.lowerBound, upper: range.upperBound)
    }

    static func parseDomain(_ bytes: [UInt8], _ range: Range<Int>) -> GeoDomain {
        var type = 2, value = ""
        var attrs: [String] = []
        var r = ProtoReader(bytes, from: range.lowerBound, to: range.upperBound)
        while !r.isAtEnd {
            guard let tag = r.readTag() else { break }
            if tag.field == 1, tag.wire == 0 {
                type = Int(r.readVarint() ?? 2)
            } else if tag.field == 2, tag.wire == 2, let s = r.readLengthDelimited() {
                value = String(decoding: bytes[s], as: UTF8.self)
            } else if tag.field == 3, tag.wire == 2, let s = r.readLengthDelimited() {
                if let key = parseAttributeKey(bytes, s) { attrs.append(key) }
            } else { r.skip(wire: tag.wire) }
        }
        return GeoDomain(kind: GeoDomain.Kind(rawValue: type) ?? .domain, value: value, attributes: attrs)
    }

    static func parseAttributeKey(_ bytes: [UInt8], _ range: Range<Int>) -> String? {
        var r = ProtoReader(bytes, from: range.lowerBound, to: range.upperBound)
        while !r.isAtEnd {
            guard let tag = r.readTag() else { break }
            if tag.field == 1, tag.wire == 2, let s = r.readLengthDelimited() {
                return String(decoding: bytes[s], as: UTF8.self)
            } else { r.skip(wire: tag.wire) }
        }
        return nil
    }

    static func parseCIDR(_ bytes: [UInt8], _ range: Range<Int>) -> GeoCIDR? {
        var ipBytes: [UInt8] = []
        var prefix = 0
        var r = ProtoReader(bytes, from: range.lowerBound, to: range.upperBound)
        while !r.isAtEnd {
            guard let tag = r.readTag() else { break }
            if tag.field == 1, tag.wire == 2, let s = r.readLengthDelimited() {
                ipBytes = Array(bytes[s])
            } else if tag.field == 2, tag.wire == 0 {
                prefix = Int(r.readVarint() ?? 0)
            } else { r.skip(wire: tag.wire) }
        }
        guard let ip = ipString(ipBytes) else { return nil }
        return GeoCIDR(ip: ip, prefix: prefix)
    }

    static func ipString(_ b: [UInt8]) -> String? {
        if b.count == 4 { return b.map(String.init).joined(separator: ".") }
        if b.count == 16 {
            var parts: [String] = []
            for i in stride(from: 0, to: 16, by: 2) {
                parts.append(String(format: "%x", Int(b[i]) << 8 | Int(b[i + 1])))
            }
            return parts.joined(separator: ":")
        }
        return nil
    }
}
