import XCTest
@testable import NetworkKit

final class HappRoutingTests: XCTestCase {
    /// A real link produced by the official Happ routing generator.
    private let realLink = "happ://routing/add/eyJOYW1lIjoiIiwiR2xvYmFsUHJveHkiOiJ0cnVlIiwiUm91dGVPcmRlciI6ImJsb2NrLXByb3h5LWRpcmVjdCIsIlJlbW90ZUROU1R5cGUiOiJEb0giLCJSZW1vdGVETlNEb21haW4iOiIiLCJSZW1vdGVETlNJUCI6IiIsIkRvbWVzdGljRE5TVHlwZSI6IkRvVSIsIkRvbWVzdGljRE5TRG9tYWluIjoiIiwiRG9tZXN0aWNETlNJUCI6IiIsIkdlb2lwdXJsIjoiIiwiR2Vvc2l0ZXVybCI6IiIsIkxhc3RVcGRhdGVkIjoiIiwiRG5zSG9zdHMiOnt9LCJEaXJlY3RTaXRlcyI6W10sIkRpcmVjdElwIjpbXSwiUHJveHlTaXRlcyI6W10sIlByb3h5SXAiOltdLCJCbG9ja1NpdGVzIjpbXSwiQmxvY2tJcCI6W10sIkRvbWFpblN0cmF0ZWd5IjoiSVBJZk5vbk1hdGNoIiwiRmFrZUROUyI6ImZhbHNlIiwiVXNlQ2h1bmtGaWxlcyI6InRydWUifQ=="

    func testDecodeRealVector() throws {
        let p = try HappRoutingLink.decode(realLink)
        XCTAssertEqual(p.name, "")
        XCTAssertTrue(p.globalProxy)
        XCTAssertEqual(p.routeOrder, "block-proxy-direct")
        XCTAssertEqual(p.remoteDNSType, "DoH")
        XCTAssertEqual(p.domesticDNSType, "DoU")
        XCTAssertEqual(p.domainStrategy, "IPIfNonMatch")
        XCTAssertFalse(p.fakeDNS)
        XCTAssertTrue(p.useChunkFiles)
        XCTAssertTrue(p.directSites.isEmpty)
        XCTAssertTrue(p.dnsHosts.isEmpty)
    }

    /// The real RoscomVPN "DEFAULT" profile — a rich config using the `onadd`
    /// verb, plain DNS fields, DnsHosts overrides and geosite/geoip tags.
    private let richLink = "happ://routing/onadd/eyJOYW1lIjoiUm9zY29tVlBOIiwiR2xvYmFsUHJveHkiOiJ0cnVlIiwiVXNlQ2h1bmtGaWxlcyI6InRydWUiLCJSZW1vdGVEbnMiOiI4LjguOC44IiwiRG9tZXN0aWNEbnMiOiI3Ny44OC44LjgiLCJSZW1vdGVETlNUeXBlIjoiRG9IIiwiUmVtb3RlRE5TRG9tYWluIjoiaHR0cHM6Ly84LjguOC44L2Rucy1xdWVyeSIsIlJlbW90ZUROU0lQIjoiOC44LjguOCIsIkRvbWVzdGljRE5TVHlwZSI6IkRvSCIsIkRvbWVzdGljRE5TRG9tYWluIjoiaHR0cHM6Ly83Ny44OC44LjgvZG5zLXF1ZXJ5IiwiRG9tZXN0aWNETlNJUCI6Ijc3Ljg4LjguOCIsIkdlb2lwdXJsIjoiaHR0cHM6Ly9jZG4uanNkZWxpdnIubmV0L2doL2h5ZHJhcG9uaXF1ZS9yb3Njb212cG4tZ2VvaXBAMjAyNjA3MjMwNjA4L3JlbGVhc2UvZ2VvaXAuZGF0IiwiR2Vvc2l0ZXVybCI6Imh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC9oeWRyYXBvbmlxdWUvcm9zY29tdnBuLWdlb3NpdGVAMjAyNjA0MTUyMjM1L3JlbGVhc2UvZ2Vvc2l0ZS5kYXQiLCJMYXN0VXBkYXRlZCI6IjE3ODQ3ODY5NjUiLCJEbnNIb3N0cyI6eyJsa2ZsMi5uYWxvZy5ydSI6IjIxMy4yNC42NC4xNzUiLCJsa25wZC5uYWxvZy5ydSI6IjIxMy4yNC42NC4xODEifSwiUm91dGVPcmRlciI6ImJsb2NrLXByb3h5LWRpcmVjdCIsIkRpcmVjdFNpdGVzIjpbImdlb3NpdGU6cHJpdmF0ZSIsImdlb3NpdGU6Y2F0ZWdvcnktcnUiLCJnZW9zaXRlOndoaXRlbGlzdCIsImdlb3NpdGU6bWljcm9zb2Z0IiwiZ2Vvc2l0ZTphcHBsZSIsImdlb3NpdGU6ZXBpY2dhbWVzIiwiZ2Vvc2l0ZTpyaW90IiwiZ2Vvc2l0ZTplc2NhcGVmcm9tdGFya292IiwiZ2Vvc2l0ZTpzdGVhbSIsImdlb3NpdGU6dHdpdGNoIiwiZ2Vvc2l0ZTpwaW50ZXJlc3QiLCJnZW9zaXRlOmZhY2VpdCJdLCJEaXJlY3RJcCI6WyJnZW9pcDpwcml2YXRlIiwiZ2VvaXA6ZGlyZWN0Il0sIlByb3h5U2l0ZXMiOlsiZ2Vvc2l0ZTpnb29nbGUtcGxheSIsImdlb3NpdGU6Z2l0aHViIiwiZ2Vvc2l0ZTp0d2l0Y2gtYWRzIiwiZ2Vvc2l0ZTp5b3V0dWJlIiwiZ2Vvc2l0ZTp0ZWxlZ3JhbSJdLCJQcm94eUlwIjpbXSwiQmxvY2tTaXRlcyI6WyJnZW9zaXRlOndpbi1zcHkiLCJnZW9zaXRlOnRvcnJlbnQiLCJnZW9zaXRlOmNhdGVnb3J5LWFkcyJdLCJCbG9ja0lwIjpbXSwiRG9tYWluU3RyYXRlZ3kiOiJJUElmTm9uTWF0Y2giLCJGYWtlRE5TIjoiZmFsc2UifQo="

    func testDecodeRichRealVector() throws {
        let p = try HappRoutingLink.decode(richLink)     // uses the onadd verb
        XCTAssertEqual(p.name, "RoscomVPN")
        XCTAssertEqual(p.remoteDNS, "8.8.8.8")
        XCTAssertEqual(p.domesticDNS, "77.88.8.8")
        XCTAssertEqual(p.remoteDNSDomain, "https://8.8.8.8/dns-query")
        XCTAssertTrue(p.geoIPURL.contains("roscomvpn-geoip"))
        XCTAssertTrue(p.geoSiteURL.contains("roscomvpn-geosite"))
        XCTAssertEqual(p.directSites.count, 12)
        XCTAssertTrue(p.directSites.contains("geosite:steam"))
        XCTAssertEqual(p.directIP, ["geoip:private", "geoip:direct"])
        XCTAssertEqual(p.proxySites.count, 5)
        XCTAssertEqual(p.blockSites.count, 3)
        XCTAssertEqual(p.ruleCount, 22)
        XCTAssertEqual(p.dnsHosts["lkfl2.nalog.ru"], "213.24.64.175")
        XCTAssertEqual(p.dnsHosts.count, 2)
        XCTAssertNotNil(p.lastUpdatedDate)
    }

    func testClassifyEntries() {
        XCTAssertEqual(HappRuleEntry.classify("geosite:youtube"), .geositeTag("youtube"))
        XCTAssertEqual(HappRuleEntry.classify("geoip:ru"), .geoipTag("ru"))
        XCTAssertEqual(HappRuleEntry.classify("1.2.3.0/24"), .ipCIDR("1.2.3.0/24"))
        XCTAssertEqual(HappRuleEntry.classify("213.24.64.175"), .ipCIDR("213.24.64.175"))
        XCTAssertEqual(HappRuleEntry.classify("2001:db8::/32"), .ipCIDR("2001:db8::/32"))
        XCTAssertEqual(HappRuleEntry.classify("example.com"), .domain("example.com"))
        XCTAssertEqual(HappRuleEntry.classify("regexp:.*\\.ru"), .raw("regexp:.*\\.ru"))
    }

    func testRoundTripPreservesFields() throws {
        let original = HappRoutingProfile(
            name: "My Provider",
            globalProxy: true,
            routeOrder: "block-proxy-direct",
            remoteDNS: "8.8.8.8",
            remoteDNSType: "DoH",
            remoteDNSDomain: "https://dns.example/dns-query",
            remoteDNSIP: "1.1.1.1",
            domesticDNS: "77.88.8.8",
            domesticDNSType: "DoU",
            domesticDNSIP: "8.8.8.8",
            geoIPURL: "https://example/geoip.dat",
            geoSiteURL: "https://example/geosite.dat",
            dnsHosts: ["router.local": "192.168.1.1"],
            directSites: ["geosite:ru", "example.com"],
            directIP: ["geoip:ru", "192.168.0.0/16"],
            proxySites: ["geosite:google"],
            proxyIP: ["8.8.8.8/32"],
            blockSites: ["geosite:category-ads-all"],
            blockIP: ["0.0.0.0/8"],
            domainStrategy: "IPOnDemand",
            fakeDNS: true,
            useChunkFiles: true
        )
        let link = try HappRoutingLink.encode(original)
        XCTAssertTrue(link.hasPrefix(HappRoutingLink.prefix))
        let decoded = try HappRoutingLink.decode(link)
        XCTAssertEqual(decoded, original)
    }

    func testDecodeAcceptsBareBase64() throws {
        let body = String(realLink.dropFirst(HappRoutingLink.prefix.count))
        let p = try HappRoutingLink.decode(body)
        XCTAssertTrue(p.globalProxy)
    }

    func testRejectsNonRoutingLink() {
        XCTAssertThrowsError(try HappRoutingLink.decode("happ://crypt5/abcdef")) { error in
            XCTAssertEqual(error as? HappRoutingLink.DecodeError, .notARoutingLink)
        }
    }

    func testRejectsGarbageBase64() {
        XCTAssertThrowsError(try HappRoutingLink.decode(HappRoutingLink.prefix + "!!!not base64!!!"))
    }

    /// The wire format keeps booleans as the strings "true"/"false".
    func testEncodeEmitsStringBooleans() throws {
        let link = try HappRoutingLink.encode(HappRoutingProfile(globalProxy: true, fakeDNS: false))
        let body = String(link.dropFirst(HappRoutingLink.prefix.count))
        let data = try XCTUnwrap(Data(base64Encoded: body))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["GlobalProxy"] as? String, "true")
        XCTAssertEqual(obj["FakeDNS"] as? String, "false")
        // Legacy link: newer-only fields stay absent until set.
        XCTAssertNil(obj["RouteOrder"])
        XCTAssertNil(obj["UseChunkFiles"])
    }
}
