import XCTest
@testable import NetworkKit

/// Parser coverage for the egress-IP probe — the body shapes of every catalog
/// resource kind, decoded without touching the network.
final class EgressIPProbeTests: XCTestCase {
    private func data(_ s: String) -> Data { Data(s.utf8) }

    // MARK: plain

    func testPlainBodyIsTrimmedIP() {
        let info = EgressIPProbe.parse(.plain, data: data("  203.0.113.7\n"))
        XCTAssertEqual(info?.ip, "203.0.113.7")
    }

    func testPlainRejectsNonIP() {
        XCTAssertNil(EgressIPProbe.parse(.plain, data: data("not-an-ip")))
        XCTAssertNil(EgressIPProbe.parse(.plain, data: data("<html>error</html>")))
    }

    func testPlainAcceptsIPv6() {
        let info = EgressIPProbe.parse(.plain, data: data("2001:db8::1"))
        XCTAssertEqual(info?.ip, "2001:db8::1")
    }

    // MARK: Cloudflare trace

    func testTraceExtractsIPCountryColo() {
        let body = "fl=123\nh=one.one.one.one\nip=198.51.100.9\nts=1.2\nloc=FR\ncolo=CDG\nwarp=off\n"
        let info = EgressIPProbe.parse(.trace, data: data(body))
        XCTAssertEqual(info?.ip, "198.51.100.9")
        XCTAssertEqual(info?.country, "FR")
        XCTAssertEqual(info?.note, "data center CDG")
    }

    func testTraceWithoutIPFails() {
        XCTAssertNil(EgressIPProbe.parse(.trace, data: data("loc=FR\ncolo=CDG\n")))
    }

    // MARK: JSON shapes

    func testIPAPIShape() {
        let body = #"{"query":"91.219.212.5","countryCode":"FR","country":"France","isp":"OVH SAS","org":"OVH","as":"AS16276 OVH SAS"}"#
        let kind = EgressResource.Kind.json(ip: ["query"], country: ["countryCode", "country"],
                                            asn: ["as"], org: ["org", "isp"])
        let info = EgressIPProbe.parse(kind, data: data(body))
        XCTAssertEqual(info?.ip, "91.219.212.5")
        XCTAssertEqual(info?.country, "FR")
        XCTAssertEqual(info?.asn, "AS16276 OVH SAS")
        XCTAssertEqual(info?.org, "OVH")
    }

    func testNestedASNNumberGetsASPrefix() {
        // ipwho.is: connection.asn is a bare number, org is nested.
        let body = #"{"ip":"91.219.212.5","country_code":"FR","connection":{"asn":16276,"org":"OVH SAS","isp":"OVH"}}"#
        let kind = EgressResource.Kind.json(ip: ["ip"], country: ["country_code", "country"],
                                            asn: ["connection.asn"], org: ["connection.org", "connection.isp"])
        let info = EgressIPProbe.parse(kind, data: data(body))
        XCTAssertEqual(info?.ip, "91.219.212.5")
        XCTAssertEqual(info?.asn, "AS16276")
        XCTAssertEqual(info?.org, "OVH SAS")
    }

    func testFirstPresentKeyWins() {
        // country_code absent → falls back to country.
        let body = #"{"ip":"203.0.113.1","country":"Germany"}"#
        let kind = EgressResource.Kind.json(ip: ["ip"], country: ["country_code", "country"], asn: [], org: [])
        XCTAssertEqual(EgressIPProbe.parse(kind, data: data(body))?.country, "Germany")
    }

    func testJSONWithBadIPFails() {
        let body = #"{"ip":"unknown","country":"FR"}"#
        let kind = EgressResource.Kind.json(ip: ["ip"], country: ["country"], asn: [], org: [])
        XCTAssertNil(EgressIPProbe.parse(kind, data: data(body)))
    }

    func testNumericASNStringGetsPrefix() {
        let body = #"{"ip":"203.0.113.1","asn":"16276"}"#
        let kind = EgressResource.Kind.json(ip: ["ip"], country: [], asn: ["asn"], org: [])
        XCTAssertEqual(EgressIPProbe.parse(kind, data: data(body))?.asn, "AS16276")
    }

    // MARK: catalog sanity

    func testCatalogURLsAreValidAndDiverse() {
        XCTAssertGreaterThanOrEqual(EgressResource.catalog.count, 15)
        for r in EgressResource.catalog {
            XCTAssertNotNil(URL(string: r.url), "bad url: \(r.url)")
        }
        // Names are unique (they're used as identity in the streamed results).
        let names = EgressResource.catalog.map(\.name)
        XCTAssertEqual(names.count, Set(names).count)
    }
}
