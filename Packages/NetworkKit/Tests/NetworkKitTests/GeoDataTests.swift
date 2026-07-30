import XCTest
@testable import NetworkKit

final class GeoDataTests: XCTestCase {

    // MARK: - Protobuf fixture encoder

    private func varint(_ v: UInt64) -> [UInt8] {
        var v = v, out: [UInt8] = []
        repeat {
            var b = UInt8(v & 0x7F); v >>= 7
            if v != 0 { b |= 0x80 }
            out.append(b)
        } while v != 0
        return out
    }
    private func tag(_ field: Int, _ wire: Int) -> [UInt8] { varint(UInt64(field << 3 | wire)) }
    private func lenField(_ field: Int, _ body: [UInt8]) -> [UInt8] {
        tag(field, 2) + varint(UInt64(body.count)) + body
    }
    private func strField(_ field: Int, _ s: String) -> [UInt8] { lenField(field, Array(s.utf8)) }
    private func varField(_ field: Int, _ v: Int) -> [UInt8] { tag(field, 0) + varint(UInt64(v)) }

    /// GeoSiteList{ GOOGLE:[domain google.com, full www.google.com @cn], CN:[domain cn.com] }
    private func geositeFixture() -> Data {
        let attrCN = strField(1, "cn")                                   // Attribute{key:"cn"}
        let dGoogle = varField(1, 2) + strField(2, "google.com")          // domain
        let dWWW = varField(1, 3) + strField(2, "www.google.com") + lenField(3, attrCN) // full + attr
        let google = strField(1, "google") + lenField(2, dGoogle) + lenField(2, dWWW)
        let dCN = varField(1, 2) + strField(2, "cn.com")
        let cn = strField(1, "cn") + lenField(2, dCN)
        return Data(lenField(1, google) + lenField(1, cn))
    }

    /// GeoIPList{ PRIVATE:[192.168.0.0/16], CN:[1.0.0.0/24] }
    private func geoipFixture() -> Data {
        let c1 = lenField(1, [192, 168, 0, 0]) + varField(2, 16)
        let priv = strField(1, "private") + lenField(2, c1)
        let c2 = lenField(1, [1, 0, 0, 0]) + varField(2, 24)
        let cn = strField(1, "cn") + lenField(2, c2)
        return Data(lenField(1, priv) + lenField(1, cn))
    }

    // MARK: - geosite

    func testGeositeIndexAndDomains() throws {
        let doc = try XCTUnwrap(GeoDataDocument.load(geositeFixture()))
        XCTAssertEqual(doc.kind, .geosite)
        XCTAssertEqual(doc.categories.map(\.code), ["GOOGLE", "CN"])
        let google = try XCTUnwrap(doc.categories.first { $0.code == "GOOGLE" })
        XCTAssertEqual(google.count, 2)

        let domains = doc.domains(in: google)
        XCTAssertEqual(domains.count, 2)
        XCTAssertEqual(domains[0].kind, .domain)
        XCTAssertEqual(domains[0].value, "google.com")
        XCTAssertEqual(domains[1].kind, .full)
        XCTAssertEqual(domains[1].value, "www.google.com")
        XCTAssertEqual(domains[1].attributes, ["cn"])
    }

    func testGeositeAutoDetect() throws {
        XCTAssertEqual(GeoDataDocument.detectKind([UInt8](geositeFixture())), .geosite)
    }

    func testCategoriesContainingDomainAndSubdomain() throws {
        let doc = try XCTUnwrap(GeoDataDocument.load(geositeFixture()))
        // full rule → exact only
        XCTAssertEqual(doc.categoriesContaining(domain: "www.google.com"), ["GOOGLE"])
        // domain rule "google.com" → subdomain matches
        XCTAssertEqual(doc.categoriesContaining(domain: "maps.google.com"), ["GOOGLE"])
        XCTAssertEqual(doc.categoriesContaining(domain: "google.com"), ["GOOGLE"])
        XCTAssertTrue(doc.categoriesContaining(domain: "example.org").isEmpty)
    }

    func testMatchSemantics() {
        XCTAssertTrue(GeoDataDocument.matches("a.example.com", rule: .init(kind: .domain, value: "example.com", attributes: [])))
        XCTAssertFalse(GeoDataDocument.matches("notexample.com", rule: .init(kind: .domain, value: "example.com", attributes: [])))
        XCTAssertTrue(GeoDataDocument.matches("foo.example.com", rule: .init(kind: .plain, value: "example", attributes: [])))
        XCTAssertTrue(GeoDataDocument.matches("example.com", rule: .init(kind: .full, value: "example.com", attributes: [])))
        XCTAssertFalse(GeoDataDocument.matches("x.example.com", rule: .init(kind: .full, value: "example.com", attributes: [])))
    }

    // MARK: - geoip

    func testGeoipIndexAndCIDRs() throws {
        let doc = try XCTUnwrap(GeoDataDocument.load(geoipFixture()))
        XCTAssertEqual(doc.kind, .geoip)
        XCTAssertEqual(doc.categories.map(\.code), ["PRIVATE", "CN"])
        let priv = try XCTUnwrap(doc.categories.first { $0.code == "PRIVATE" })
        let cidrs = doc.cidrs(in: priv)
        XCTAssertEqual(cidrs.map(\.text), ["192.168.0.0/16"])
    }

    func testGeoipAutoDetect() throws {
        XCTAssertEqual(GeoDataDocument.detectKind([UInt8](geoipFixture())), .geoip)
    }

    func testIPv6Formatting() {
        let v6: [UInt8] = [0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
        XCTAssertEqual(GeoDataDocument.ipString(v6), "2001:db8:0:0:0:0:0:1")
        XCTAssertNil(GeoDataDocument.ipString([1, 2, 3]))
    }

    func testEmptyIsNil() {
        XCTAssertNil(GeoDataDocument.load(Data()))
    }

    // MARK: - Live (network-gated): a real geosite.dat / geoip.dat

    func testLiveRealGeositeParses() async throws {
        try requiresInternet()
        let url = URL(string: "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let doc = try XCTUnwrap(GeoDataDocument.load(data, kind: .geosite))
        XCTAssertGreaterThan(doc.categories.count, 100)
        // Well-known categories every build ships.
        let codes = Set(doc.categories.map(\.code))
        XCTAssertTrue(codes.contains("GOOGLE"))
        XCTAssertTrue(codes.contains("NETFLIX"))
        let cn = try XCTUnwrap(doc.categories.first { $0.code == "CN" })
        XCTAssertGreaterThan(cn.count, 1000)
        XCTAssertFalse(doc.domains(in: cn).isEmpty)
    }

    func testLiveRealGeoipParses() async throws {
        try requiresInternet()
        let url = URL(string: "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let doc = try XCTUnwrap(GeoDataDocument.load(data, kind: .geoip))
        XCTAssertEqual(doc.kind, .geoip)
        let cn = try XCTUnwrap(doc.categories.first { $0.code == "CN" })
        let cidrs = doc.cidrs(in: cn)
        XCTAssertGreaterThan(cidrs.count, 100)
        // CN ships both IPv4 and IPv6 ranges (prefix up to /128).
        XCTAssertTrue(cidrs.allSatisfy { $0.prefix > 0 && $0.prefix <= 128 })
        XCTAssertTrue(cidrs.contains { $0.ip.contains(".") })   // has IPv4
        // A known Chinese IPv4 resolves to the CN category.
        XCTAssertTrue(doc.categoriesContaining(ip: "1.2.4.8").contains("CN"))
    }
}
