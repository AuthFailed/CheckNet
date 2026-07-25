import XCTest
@testable import NetworkKit

final class RealityScannerTests: XCTestCase {

    // MARK: - Pure logic

    func testCommonNameExtraction() {
        XCTAssertEqual(RealityScanner.commonName(from: "CN=www.example.com, O=Example"), "www.example.com")
        XCTAssertEqual(RealityScanner.commonName(from: "O=Foo, CN=a.b.c"), "a.b.c")
        XCTAssertNil(RealityScanner.commonName(from: "O=NoCommonName"))
        XCTAssertNil(RealityScanner.commonName(from: nil))
    }

    func testResolveTargetsExpandsCIDR() async {
        let hosts = await RealityScanner.resolveTargets("192.168.10.0/30", port: 443)
        // /30 → two usable hosts.
        XCTAssertEqual(hosts, ["192.168.10.1", "192.168.10.2"])
    }

    func testResolveTargetsSingleIP() async {
        let hosts = await RealityScanner.resolveTargets("203.0.113.5", port: 443)
        XCTAssertEqual(hosts, ["203.0.113.5"])
    }

    func testResolveTargetsDashRange() async {
        let hosts = await RealityScanner.resolveTargets("10.0.0.1-3", port: 443)
        XCTAssertEqual(hosts, ["10.0.0.1", "10.0.0.2", "10.0.0.3"])
    }

    // MARK: - Live (network-gated)

    func testLiveScanSingleTLS13Host() async throws {
        try requiresInternet()
        // 8.8.8.8 serves a default certificate (dns.google) over TLS 1.3 + h2 even
        // without SNI — unlike 1.1.1.1, which requires SNI and answers nothing.
        var hits: [RealityScanHit] = []
        var finished = false
        for await event in RealityScanner().scan(target: "8.8.8.8", timeout: 6) {
            switch event {
            case .hit(let h): hits.append(h)
            case .finished: finished = true
            case .failed(let m): XCTFail("scan failed: \(m)")
            case .progress: break
            }
        }
        XCTAssertTrue(finished)
        let hit = try XCTUnwrap(hits.first)
        XCTAssertEqual(hit.tlsVersion, "TLS 1.3")
        XCTAssertFalse(hit.domain.isEmpty)
        XCTAssertTrue(hit.supportsH2)
    }

    func testLiveScanRejectsNonTLSHost() async throws {
        try requiresInternet()
        // Port 443 on a host that won't complete a TLS handshake here → no hit,
        // but the scan must still finish cleanly.
        var hitCount = 0
        var finished = false
        for await event in RealityScanner().scan(target: "192.0.2.1", timeout: 3) {
            switch event {
            case .hit: hitCount += 1
            case .finished(let c): finished = true; XCTAssertEqual(c, hitCount)
            default: break
            }
        }
        XCTAssertTrue(finished)
        XCTAssertEqual(hitCount, 0)   // TEST-NET-1 is unrouted.
    }

    func testInvalidTargetFails() async {
        var failed = false
        for await event in RealityScanner().scan(target: "not an address", timeout: 2) {
            if case .failed = event { failed = true }
        }
        XCTAssertTrue(failed)
    }
}
