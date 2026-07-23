import XCTest
@testable import NetworkKit

final class IPGeolocationTests: XCTestCase {

    private func data(_ s: String) -> Data { Data(s.utf8) }

    // MARK: ipwho.is

    private let ipwhoisBody = """
    {"ip":"1.1.1.1","success":true,"type":"IPv4","country":"Australia","country_code":"AU",
     "region":"Queensland","city":"Brisbane","latitude":-27.4675408,"longitude":153.028092,
     "connection":{"asn":13335,"org":"Apnic Research And Development","isp":"Cloudflare, Inc."},
     "timezone":{"id":"Australia/Brisbane"}}
    """

    func testParseIpwhois() throws {
        let r = try XCTUnwrap(IPGeolocation.parseIpwhois(data(ipwhoisBody)))
        XCTAssertEqual(r.ip, "1.1.1.1")
        XCTAssertEqual(r.country, "Australia")
        XCTAssertEqual(r.countryCode, "AU")
        XCTAssertEqual(r.city, "Brisbane")
        XCTAssertEqual(r.asn, "AS13335")
        XCTAssertEqual(r.asnOrg, "Apnic Research And Development")
        XCTAssertEqual(r.isp, "Cloudflare, Inc.")
        XCTAssertEqual(r.timezone, "Australia/Brisbane")
        XCTAssertEqual(r.latitude ?? 0, -27.4675408, accuracy: 0.0001)
        XCTAssertEqual(r.source, "ipwho.is")
    }

    func testParseIpwhoisFailureBodyRejected() {
        // A rate-limit / error body has success:false — not a real answer.
        XCTAssertNil(IPGeolocation.parseIpwhois(data(#"{"success":false,"message":"Invalid IP"}"#)))
    }

    // MARK: ipquery.io

    private let ipqueryBody = """
    {"ip":"1.1.1.1","isp":{"asn":"AS13335","org":"Cloudflare, Inc.","isp":"Cloudflare, Inc."},
     "location":{"country":"Australia","country_code":"AU","city":"Sydney","state":"New South Wales",
     "latitude":-33.87,"longitude":151.22,"timezone":"Australia/Sydney"},
     "risk":{"is_mobile":false,"is_vpn":false,"is_tor":false,"is_proxy":false,"is_datacenter":true}}
    """

    func testParseIpquery() throws {
        let r = try XCTUnwrap(IPGeolocation.parseIpquery(data(ipqueryBody)))
        XCTAssertEqual(r.ip, "1.1.1.1")
        XCTAssertEqual(r.country, "Australia")
        XCTAssertEqual(r.city, "Sydney")
        XCTAssertEqual(r.region, "New South Wales")
        XCTAssertEqual(r.asn, "AS13335")
        XCTAssertEqual(r.isHosting, true)
        XCTAssertEqual(r.isVPN, false)
        XCTAssertEqual(r.source, "ipquery.io")
    }

    func testParseIpqueryBareIPRejected() {
        // The own-IP path returns bare text like "1.2.3.4" — not a geolocation.
        XCTAssertNil(IPGeolocation.parseIpquery(data("88.214.24.82")))
    }

    // MARK: Derived fields

    func testFlagEmoji() throws {
        let au = try XCTUnwrap(IPGeolocation.parseIpwhois(data(ipwhoisBody)))
        XCTAssertEqual(au.flagEmoji, "🇦🇺")
    }

    func testFlagEmojiRejectsBadCode() {
        func result(cc: String?) -> IPGeoResult {
            IPGeoResult(ip: "x", country: nil, countryCode: cc, region: nil, city: nil,
                        latitude: nil, longitude: nil, asn: nil, asnOrg: nil, isp: nil,
                        timezone: nil, isHosting: nil, isVPN: nil, isProxy: nil, isTor: nil, source: "t")
        }
        XCTAssertEqual(result(cc: "US").flagEmoji, "🇺🇸")
        XCTAssertNil(result(cc: "XYZ").flagEmoji)
        XCTAssertNil(result(cc: "1").flagEmoji)
        XCTAssertNil(result(cc: nil).flagEmoji)
    }

    func testASNumberStripsPrefix() throws {
        let r = try XCTUnwrap(IPGeolocation.parseIpquery(data(ipqueryBody)))
        XCTAssertEqual(r.asNumber, "13335")
    }

    // MARK: End-to-end (network)

    func testLocateRealIP() async throws {
        try requiresInternet()
        let r = try await IPGeolocation().locate(query: "1.1.1.1")
        XCTAssertEqual(r.ip, "1.1.1.1")
        XCTAssertNotNil(r.country, "a real lookup should carry a country")
        XCTAssertEqual(r.asNumber, "13335", "1.1.1.1 is Cloudflare AS13335")
        print("geo 1.1.1.1 via \(r.source): \(r.flagEmoji ?? "") \(r.country ?? "?"), \(r.city ?? "?"), \(r.asn ?? "?") \(r.asnOrg ?? "")")
    }

    func testLocateOwnIP() async throws {
        try requiresInternet()
        let r = try await IPGeolocation().locate(query: "")
        XCTAssertFalse(r.ip.isEmpty, "own-IP lookup should return an address")
        print("geo own via \(r.source): \(r.ip) — \(r.country ?? "?")")
    }
}
