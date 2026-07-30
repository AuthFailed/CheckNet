import XCTest
@testable import NetworkKit

/// Real `.mrs` fixtures from MetaCubeX/meta-rules-dat (tiny public rule-sets),
/// embedded so the whole zstd → container → payload pipeline is tested offline.
/// Expected values were derived independently (Python + `zstd -dc`).
final class MRSParserTests: XCTestCase {
    private func data(_ b64: String) -> Data { Data(base64Encoded: b64)! }

    // geo/geosite/0x0.mrs — a single domain rule.
    private let dom0x0 = "KLUv/QQALQEARAFNUlMBAAFAAAGqqgh0cy4weDAuKwYAIM/MAcAYmhmwTIDrtLCfVU0="
    // geo/geoip/telegram.mrs — 12 source CIDRs, 10 merged ranges, IPv4 + IPv6.
    private let ipTelegram = "KLUv/UQAXgAVBACkBE1SUwEBAAwAAAoAAP//W2nAwf9sBAAX/zgAO/9foUAAT/+VmqAAr/+5TJcA/yABBnwE6P8gAQso8jwAPT8/KgrygAAAKgrygP//HCBQw8g8YJfgpu2o82C2IOJ5rRSjHEb4AYHZERyWSQ6TCYfLmIzl0YMTOQxiIZciQelgDAwOzA2wmg=="
    // geo/geoip/twitter.mrs — 20 source CIDRs, 18 merged ranges.
    private let ipTwitter = "KLUv/UQAXgG9BQAkB01SUwEBABQAABIAAP//CBnCxf9APz//RQw4AGf8cGf8c2j0KWj0KiwvuS0EuS0HvEDgvEDnwDDswDDthUyFT8cQnMcQnzuUO5dgOGA5yqCAyqCD0e3Q0e3Q/yQAZoDwJABmgP8mBh8mBh8qBJ1AKgSdQCoogMMwFxACBEYAQO0GIQg3Ro4BYm0EwsfBaIANgxkbB2Fwx8FoMBhyyTq4LvExCwSRQAiNMeDUwzh2c4kM6sFwFg6JgmnQ"

    func testDomainSmallSet() throws {
        // Encodes both an exact and a suffix rule (leaves bitmap has two bits);
        // verified against an independent LOUDS decode.
        let set = try MRSParser.parse(data(dom0x0))
        XCTAssertEqual(set.behavior, .domain)
        XCTAssertEqual(set.domains, ["0x0.st", "+.0x0.st"])
        XCTAssertTrue(set.cidrs.isEmpty)
    }

    func testIpCidrTelegramExactBlocks() throws {
        let set = try MRSParser.parse(data(ipTelegram))
        XCTAssertEqual(set.behavior, .ipcidr)
        XCTAssertEqual(set.entryCount, 12)          // header count = source CIDRs
        XCTAssertEqual(set.cidrs, [
            "91.105.192.0/23", "91.108.4.0/22", "91.108.8.0/21", "91.108.16.0/21",
            "91.108.56.0/22", "95.161.64.0/20", "149.154.160.0/20", "185.76.151.0/24",
            "2001:67c:4e8::/48", "2001:b28:f23c::/47", "2001:b28:f23f::/48", "2a0a:f280::/32",
        ])
    }

    func testIpCidrTwitterCountAndHead() throws {
        let set = try MRSParser.parse(data(ipTwitter))
        XCTAssertEqual(set.behavior, .ipcidr)
        XCTAssertEqual(set.entryCount, 20)
        XCTAssertEqual(set.cidrs.count, 20)
        XCTAssertEqual(Array(set.cidrs.prefix(3)), ["8.25.194.0/23", "8.25.196.0/23", "64.63.0.0/18"])
        XCTAssertTrue(set.cidrs.contains("104.244.41.0/24"))   // a well-known Twitter block
    }

    func testDomainLargeSetEnumeration() throws {
        let set = try MRSParser.parse(data(MRSFixtures.youtube))
        XCTAssertEqual(set.behavior, .domain)
        XCTAssertEqual(set.domains.count, 355)
        XCTAssertTrue(set.domains.contains("+.youtube.com"))
        XCTAssertTrue(set.domains.contains("+.googlevideo.com"))
        XCTAssertTrue(set.domains.contains("+.ggpht.com"))
        // No duplicates, all non-empty.
        XCTAssertEqual(Set(set.domains).count, set.domains.count)
        XCTAssertFalse(set.domains.contains(where: \.isEmpty))
    }

    func testDomainLimitCaps() throws {
        let raw = try Zstd.decompress(data(MRSFixtures.youtube))
        var r = ByteReader(raw)
        _ = try r.take(4); _ = try r.u8(); _ = try r.i64(); _ = try r.i64()  // skip container header
        let set = try SuccinctDomainSet.read(&r)
        XCTAssertEqual(set.domains(limit: 10).count, 10)
        XCTAssertEqual(set.domains().count, 355)
    }

    func testZstdRoundTripHeader() throws {
        let raw = try Zstd.decompress(data(ipTelegram))
        XCTAssertEqual(Array(raw.prefix(4)), [0x4D, 0x52, 0x53, 0x01])  // "MRS\x01"
    }

    func testRejectsNonZstd() {
        XCTAssertThrowsError(try MRSParser.parse(Data("not a mrs file".utf8))) { err in
            XCTAssertEqual(err as? MRSParser.ParseError, .notCompressed)
        }
    }

    func testRejectsBadMagic() {
        // A valid empty-ish decompressed buffer with wrong magic.
        var bad = Data([0x00, 0x00, 0x00, 0x00, 0x00])
        bad.append(Data(repeating: 0, count: 16))
        XCTAssertThrowsError(try MRSParser.parseDecompressed(bad)) { err in
            XCTAssertEqual(err as? MRSParser.ParseError, .badMagic)
        }
    }

    func testRangeToCIDRSingleHost() {
        // 1.2.3.4 – 1.2.3.4 → a /32.
        let f = [UInt8](repeating: 0, count: 10) + [0xFF, 0xFF, 1, 2, 3, 4]
        XCTAssertEqual(IPRangeCIDR.blocks(from16: f, to16: f), ["1.2.3.4/32"])
    }
}
