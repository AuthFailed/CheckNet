import XCTest
@testable import NetworkKit

final class ScanTests: XCTestCase {
    // MARK: IPv4 range parsing

    func testCIDRParsing() {
        let hosts = IPv4Range.hosts(from: "192.168.1.0/24")
        XCTAssertEqual(hosts?.count, 254)
        XCTAssertEqual(hosts?.first, "192.168.1.1")
        XCTAssertEqual(hosts?.last, "192.168.1.254")
    }

    func testDashRangeParsing() {
        XCTAssertEqual(IPv4Range.hosts(from: "10.0.0.5-10.0.0.8"), ["10.0.0.5", "10.0.0.6", "10.0.0.7", "10.0.0.8"])
        XCTAssertEqual(IPv4Range.hosts(from: "10.0.0.5-8"), ["10.0.0.5", "10.0.0.6", "10.0.0.7", "10.0.0.8"])
    }

    func testBaseParsing() {
        let hosts = IPv4Range.hosts(from: "192.168.0")
        XCTAssertEqual(hosts?.count, 254)
    }

    func testInvalidRange() {
        XCTAssertNil(IPv4Range.hosts(from: "not-an-ip"))
        XCTAssertNil(IPv4Range.hosts(from: "1.2.3.4/33"))
    }

    func testUInt32RoundTrip() {
        XCTAssertEqual(IPv4Range.toString(IPv4Range.toUInt32("8.8.4.4")!), "8.8.4.4")
    }

    // MARK: MTU discovery

    func testMTUDiscovery() async throws {
        try requiresInternet()
        var result: MTUResult?
        for await progress in MTUDiscovery().discover(host: "1.1.1.1", perProbeTimeout: 1.0) {
            if case .finished(let r) = progress { result = r }
        }
        let r = try XCTUnwrap(result, "MTU discovery produced no result")
        print("path MTU to 1.1.1.1: \(r.pathMTU) (payload \(r.maxPayload)), \(r.probes.count) probes")
        // A normal internet path is between 576 and 1500.
        XCTAssertGreaterThanOrEqual(r.pathMTU, 576)
        XCTAssertLessThanOrEqual(r.pathMTU, 1500)
    }

    // MARK: IP range scan (small, local loopback-ish range to stay fast)

    func testRangeScanFindsHost() async throws {
        try requiresInternet()
        // 1.1.1.1 and 1.0.0.1 both answer; scan the tiny range around them.
        var alive: [DiscoveredHost] = []
        for await event in IPRangeScanner().scan(range: "1.1.1.1-1.1.1.1", timeout: 2.0, resolveNames: false) {
            if case .host(let h) = event { alive.append(h) }
        }
        print("alive in range: \(alive.map(\.ip))")
        XCTAssertTrue(alive.contains { $0.ip == "1.1.1.1" }, "expected 1.1.1.1 alive")
    }
}
