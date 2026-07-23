import XCTest
@testable import NetworkKit

final class IPGeolocationTests: XCTestCase {

    private func data(_ s: String) -> Data { Data(s.utf8) }

    private func result(source: String, country: String?, cc: String?, city: String?,
                        asn: String?, lat: Double? = nil, hosting: Bool? = nil) -> IPGeoResult {
        IPGeoResult(ip: "8.8.8.8", country: country, countryCode: cc, region: nil, city: city,
                    latitude: lat, longitude: nil, asn: asn, asnOrg: nil, isp: nil, timezone: nil,
                    isHosting: hosting, isVPN: nil, isProxy: nil, isTor: nil, source: source)
    }

    // MARK: Parsers

    func testParseIpapi() throws {
        let body = #"{"status":"success","country":"United States","countryCode":"US","regionName":"Virginia","city":"Ashburn","lat":39.03,"lon":-77.5,"timezone":"America/New_York","isp":"Google LLC","org":"Google Public DNS","as":"AS15169 Google LLC","asname":"GOOGLE","mobile":false,"proxy":false,"hosting":true,"query":"8.8.8.8"}"#
        let r = try XCTUnwrap(IPGeolocation.parseIpapi(data(body)))
        XCTAssertEqual(r.ip, "8.8.8.8")
        XCTAssertEqual(r.country, "United States")
        XCTAssertEqual(r.city, "Ashburn")
        XCTAssertEqual(r.asn, "AS15169")
        XCTAssertEqual(r.asnOrg, "Google LLC")     // parsed out of the "as" field
        XCTAssertEqual(r.isHosting, true)
        XCTAssertEqual(r.isProxy, false)
        XCTAssertEqual(r.source, "ip-api.com")
    }

    func testParseIpapiFailStatusRejected() {
        XCTAssertNil(IPGeolocation.parseIpapi(data(#"{"status":"fail","message":"private range","query":"10.0.0.1"}"#)))
    }

    func testParseIpwhois() throws {
        let body = #"{"ip":"1.1.1.1","success":true,"country":"Australia","country_code":"AU","city":"Brisbane","latitude":-27.46,"longitude":153.02,"connection":{"asn":13335,"org":"Cloudflare","isp":"Cloudflare, Inc."},"timezone":{"id":"Australia/Brisbane"}}"#
        let r = try XCTUnwrap(IPGeolocation.parseIpwhois(data(body)))
        XCTAssertEqual(r.countryCode, "AU")
        XCTAssertEqual(r.asn, "AS13335")
        XCTAssertEqual(r.source, "ipwho.is")
    }

    func testParseIpwhoisFailureBodyRejected() {
        XCTAssertNil(IPGeolocation.parseIpwhois(data(#"{"success":false,"message":"Invalid IP"}"#)))
    }

    func testParseIpquery() throws {
        let body = #"{"ip":"1.1.1.1","isp":{"asn":"AS13335","org":"Cloudflare, Inc.","isp":"Cloudflare, Inc."},"location":{"country":"Australia","country_code":"AU","city":"Sydney","state":"NSW","latitude":-33.8,"longitude":151.2,"timezone":"Australia/Sydney"},"risk":{"is_vpn":false,"is_datacenter":true,"is_proxy":false,"is_tor":false}}"#
        let r = try XCTUnwrap(IPGeolocation.parseIpquery(data(body)))
        XCTAssertEqual(r.asn, "AS13335")
        XCTAssertEqual(r.isHosting, true)
        XCTAssertEqual(r.source, "ipquery.io")
    }

    func testParseIpqueryBareIPRejected() {
        XCTAssertNil(IPGeolocation.parseIpquery(data("88.214.24.82")))
    }

    func testParseDbip() throws {
        let body = #"{"ipAddress":"8.8.8.8","continentCode":"NA","countryCode":"US","countryName":"United States","stateProv":"California","city":"Mountain View"}"#
        let r = try XCTUnwrap(IPGeolocation.parseDbip(data(body)))
        XCTAssertEqual(r.country, "United States")
        XCTAssertEqual(r.city, "Mountain View")
        XCTAssertNil(r.asn, "DB-IP free has no ASN")
        XCTAssertEqual(r.source, "DB-IP")
    }

    func testParseDbipErrorBodyRejected() {
        XCTAssertNil(IPGeolocation.parseDbip(data(#"{"error":"rate limited"}"#)))
    }

    func testParseFreeipapi() throws {
        let body = #"{"ipVersion":4,"ipAddress":"8.8.8.8","latitude":37.42,"longitude":-122.08,"countryName":"United States","countryCode":"US","timeZones":["America/Los_Angeles"],"cityName":"Mountain View","regionName":"California","asn":"15169","asnOrganization":"GOOGLE"}"#
        let r = try XCTUnwrap(IPGeolocation.parseFreeipapi(data(body)))
        XCTAssertEqual(r.country, "United States")
        XCTAssertEqual(r.city, "Mountain View")
        XCTAssertEqual(r.asn, "AS15169")           // "15169" gets the AS prefix
        XCTAssertEqual(r.timezone, "America/Los_Angeles")
        XCTAssertEqual(r.source, "freeipapi.com")
    }

    // MARK: Derived

    func testFlagEmoji() {
        XCTAssertEqual(result(source: "t", country: nil, cc: "US", city: nil, asn: nil).flagEmoji, "🇺🇸")
        XCTAssertEqual(result(source: "t", country: nil, cc: "AU", city: nil, asn: nil).flagEmoji, "🇦🇺")
        XCTAssertNil(result(source: "t", country: nil, cc: "XYZ", city: nil, asn: nil).flagEmoji)
        XCTAssertNil(result(source: "t", country: nil, cc: nil, city: nil, asn: nil).flagEmoji)
    }

    func testASNumberStripsPrefix() {
        XCTAssertEqual(result(source: "t", country: nil, cc: nil, city: nil, asn: "AS13335").asNumber, "13335")
        XCTAssertNil(result(source: "t", country: nil, cc: nil, city: nil, asn: nil).asNumber)
    }

    // MARK: Consensus

    func testConsolidateMajorityWins() {
        let results = [
            result(source: "a", country: "United States", cc: "US", city: "Ashburn", asn: "AS15169", lat: 39.0),
            result(source: "b", country: "United States", cc: "US", city: "Mountain View", asn: "AS15169", lat: 37.4),
            result(source: "c", country: "Canada", cc: "CA", city: "Toronto", asn: "AS577", lat: 43.7)
        ]
        let c = IPGeolocation.consolidate(results, ip: "8.8.8.8")
        XCTAssertEqual(c.country, "United States")   // 2 vs 1
        XCTAssertEqual(c.countryCode, "US")
        XCTAssertEqual(c.asn, "AS15169")
        XCTAssertEqual(c.sourceCount, 3)
        XCTAssertEqual(c.latitude, 39.0)             // median of [37.4, 39.0, 43.7]
    }

    func testConsolidateTieKeepsEarlierProvider() {
        let results = [
            result(source: "a", country: "United States", cc: "US", city: nil, asn: nil),
            result(source: "b", country: "Canada", cc: "CA", city: nil, asn: nil)
        ]
        // 1–1 tie → the earlier provider's value.
        XCTAssertEqual(IPGeolocation.consolidate(results, ip: "8.8.8.8").country, "United States")
    }

    func testConsolidateFlagsAnyTrue() {
        let results = [
            result(source: "a", country: "US", cc: "US", city: nil, asn: nil, hosting: false),
            result(source: "b", country: "US", cc: "US", city: nil, asn: nil, hosting: true)
        ]
        XCTAssertEqual(IPGeolocation.consolidate(results, ip: "8.8.8.8").isHosting, true)
    }

    // MARK: End-to-end (network)

    func testLookupRealIP() async throws {
        try requiresInternet()
        let lookup = try await IPGeolocation().lookup(query: "1.1.1.1")
        XCTAssertEqual(lookup.ip, "1.1.1.1")
        XCTAssertGreaterThanOrEqual(lookup.providers.count, 2, "several providers should answer")
        XCTAssertEqual(lookup.consensus.asNumber, "13335", "1.1.1.1 is Cloudflare AS13335")
        XCTAssertNotNil(lookup.consensus.country)
        // No duplicate sources.
        XCTAssertEqual(Set(lookup.providers.map(\.source)).count, lookup.providers.count)
        print("geo 1.1.1.1: consensus \(lookup.consensus.flagEmoji ?? "") \(lookup.consensus.country ?? "?"), \(lookup.consensus.asn ?? "?") from \(lookup.providers.count) sources: \(lookup.providers.map(\.source))")
    }

    func testLookupOwnIP() async throws {
        try requiresInternet()
        let lookup = try await IPGeolocation().lookup(query: "")
        XCTAssertFalse(lookup.ip.isEmpty)
        XCTAssertFalse(lookup.providers.isEmpty)
    }
}
