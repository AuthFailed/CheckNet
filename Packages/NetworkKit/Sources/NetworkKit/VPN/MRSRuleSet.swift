import Foundation

/// A parsed mihomo (Clash.Meta) `.mrs` rule-set. The file is a zstd frame
/// wrapping `MRS\x01`, a behaviour byte, an entry count, a reserved block, then a
/// behaviour-specific payload: a succinct domain set, or a list of merged IP
/// ranges. This is a **viewer** — we decode and list, we never route.
public struct MRSRuleSet: Sendable, Equatable {
    public enum Behavior: String, Sendable { case domain, ipcidr }

    public let behavior: Behavior
    /// The entry count stored in the header (source rules before merging).
    public let entryCount: Int
    /// Domain rules (domain behaviour), reconstructed from the succinct trie.
    public let domains: [String]
    /// CIDRs (ipcidr behaviour), expanded from the stored merged ranges.
    public let cidrs: [String]

    public var itemCount: Int { behavior == .domain ? domains.count : cidrs.count }
}

public enum MRSParser {
    public enum ParseError: Error, Equatable, Sendable {
        case notCompressed, badMagic, badVersion, unsupportedBehavior(UInt8), truncated
    }

    static let magic: [UInt8] = [0x4D, 0x52, 0x53, 0x01] // "MRS" + version 1

    /// Parse raw `.mrs` file bytes (still zstd-compressed).
    public static func parse(_ fileData: Data) throws -> MRSRuleSet {
        let raw: Data
        do { raw = try Zstd.decompress(fileData) }
        catch Zstd.Failure.notZstd { throw ParseError.notCompressed }
        catch { throw ParseError.truncated }
        return try parseDecompressed(raw)
    }

    /// Parse the already-decompressed container (exposed for tests).
    static func parseDecompressed(_ raw: Data) throws -> MRSRuleSet {
        var r = ByteReader(raw)
        guard try r.take(4).elementsEqual(magic) else { throw ParseError.badMagic }
        let behaviorByte = try r.u8()
        let count = try r.i64()
        let extra = try r.i64()
        guard extra >= 0 else { throw ParseError.truncated }
        if extra > 0 { _ = try r.take(Int(extra)) }

        switch behaviorByte {
        case 0:
            let set = try SuccinctDomainSet.read(&r)
            return MRSRuleSet(behavior: .domain, entryCount: Int(max(0, count)),
                              domains: set.domains(), cidrs: [])
        case 1:
            let cidrs = try IpCidrPayload.read(&r)
            return MRSRuleSet(behavior: .ipcidr, entryCount: Int(max(0, count)),
                              domains: [], cidrs: cidrs)
        default:
            throw ParseError.unsupportedBehavior(behaviorByte)
        }
    }
}

/// Big-endian byte cursor over a `.mrs` payload.
struct ByteReader {
    let bytes: [UInt8]
    var offset = 0
    init(_ data: Data) { bytes = [UInt8](data) }
    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var remaining: Int { bytes.count - offset }

    mutating func take(_ n: Int) throws -> ArraySlice<UInt8> {
        guard n >= 0, offset + n <= bytes.count else { throw MRSParser.ParseError.truncated }
        defer { offset += n }
        return bytes[offset ..< offset + n]
    }

    mutating func u8() throws -> UInt8 {
        guard offset < bytes.count else { throw MRSParser.ParseError.truncated }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func u64() throws -> UInt64 {
        let s = try take(8)
        return s.reduce(0) { ($0 << 8) | UInt64($1) }
    }

    mutating func i64() throws -> Int64 { Int64(bitPattern: try u64()) }

    /// Read an `int64` length then that many big-endian `uint64` words.
    mutating func u64Array() throws -> [UInt64] {
        let n = try i64()
        guard n >= 0, n <= Int64(remaining / 8) else { throw MRSParser.ParseError.truncated }
        var out = [UInt64](); out.reserveCapacity(Int(n))
        for _ in 0 ..< n { out.append(try u64()) }
        return out
    }
}

/// The ipcidr payload: `version`, an `int64` range count, then each range as two
/// 16-byte big-endian addresses [from, to]. We expand every range into minimal
/// CIDR blocks for display (IPv4 when the address is v4-mapped, else IPv6).
enum IpCidrPayload {
    static func read(_ r: inout ByteReader) throws -> [String] {
        let version = try r.u8()
        guard version == 1 else { throw MRSParser.ParseError.badVersion }
        let count = try r.i64()
        guard count >= 0, count <= Int64(r.remaining / 32) else { throw MRSParser.ParseError.truncated }

        var cidrs: [String] = []
        for _ in 0 ..< count {
            let from = Array(try r.take(16))
            let to = Array(try r.take(16))
            cidrs.append(contentsOf: IPRangeCIDR.blocks(from16: from, to16: to))
        }
        return cidrs
    }
}
