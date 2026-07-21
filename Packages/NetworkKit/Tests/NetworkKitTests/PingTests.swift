import XCTest
@testable import NetworkKit

final class PingTests: XCTestCase {
    func testResolveKnownHost() async throws {
        try requiresInternet()
        let endpoints = try await HostResolver.resolve(host: "one.one.one.one", family: .ipv4)
        XCTAssertFalse(endpoints.isEmpty)
        XCTAssertTrue(endpoints.allSatisfy { $0.family == .ipv4 })
        // Cloudflare resolves to 1.1.1.1 / 1.0.0.1
        XCTAssertTrue(endpoints.contains { $0.ipString == "1.1.1.1" || $0.ipString == "1.0.0.1" },
                      "got: \(endpoints.map(\.ipString))")
    }

    func testResolveIPLiteral() async throws {
        let ep = try await HostResolver.resolveFirst(host: "8.8.8.8", family: .ipv4)
        XCTAssertEqual(ep.ipString, "8.8.8.8")
        XCTAssertEqual(ep.family, .ipv4)
    }

    func testPingCloudflare() async throws {
        try requiresInternet()
        let pinger = ICMPPinger()
        let config = PingConfig(count: 4, interval: 0.2, timeout: 2.0)
        var replies = 0
        var started = false
        var stats: PingStatistics?
        for await event in pinger.ping(host: "1.1.1.1", config: config) {
            switch event {
            case .started(let ip, let fam):
                started = true
                XCTAssertEqual(ip, "1.1.1.1")
                XCTAssertEqual(fam, .ipv4)
            case .reply(let r):
                replies += 1
                XCTAssertGreaterThan(r.rttMillis, 0)
                XCTAssertLessThan(r.rttMillis, 2000)
            case .finished(let s):
                stats = s
            default:
                break
            }
        }
        XCTAssertTrue(started)
        let s = try XCTUnwrap(stats)
        XCTAssertEqual(s.transmitted, 4)
        // Expect at least one reply on a healthy network.
        XCTAssertGreaterThanOrEqual(replies, 1, "no ICMP replies received")
        XCTAssertGreaterThanOrEqual(s.received, 1)
        print("PING 1.1.1.1 -> recv=\(s.received)/\(s.transmitted) loss=\(s.lossPercent)% avg=\(s.avg ?? -1)ms ttl-sample")
    }

    func testPingReportsTTL() async throws {
        try requiresInternet()
        let pinger = ICMPPinger()
        var ttls: [Int] = []
        for await event in pinger.ping(host: "8.8.8.8", config: PingConfig(count: 3, interval: 0.2, timeout: 2)) {
            if case .reply(let r) = event, let t = r.ttl { ttls.append(t) }
        }
        print("TTLs from 8.8.8.8: \(ttls)")
        // TTL is best-effort; if present it should be a sane hop value.
        for t in ttls { XCTAssertTrue((1...255).contains(t)) }
    }

    func testPingBadHostSurfacesFailure() async throws {
        try requiresInternet()
        let pinger = ICMPPinger()
        var failure: String?
        var finishedOK = false
        for await event in pinger.ping(host: "no-such-host.invalid", config: PingConfig(count: 2, timeout: 1)) {
            switch event {
            case .failed(let reason): failure = reason
            case .finished: finishedOK = true
            default: break
            }
        }
        XCTAssertNotNil(failure, "bad host should surface a .failed event, not finish silently")
        XCTAssertFalse(finishedOK, "should not emit .finished on resolution failure")
        print("bad host failure: \(failure ?? "-")")
    }

    func testPingStatisticsMath() {
        var s = PingStatistics(host: "h", resolvedIP: "1.2.3.4", transmitted: 4, received: 3)
        s.rttSamples = [10, 20, 30]
        XCTAssertEqual(s.min, 10)
        XCTAssertEqual(s.max, 30)
        XCTAssertEqual(s.avg, 20)
        XCTAssertEqual(s.lossPercent, 25)
        XCTAssertEqual(s.jitter, 10) // |20-10| + |30-20| = 20 / 2
    }
}
