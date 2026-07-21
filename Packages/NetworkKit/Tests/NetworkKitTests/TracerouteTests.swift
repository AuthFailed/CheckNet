import XCTest
@testable import NetworkKit

final class TracerouteTests: XCTestCase {
    func testTraceToCloudflare() async throws {
        try requiresInternet()
        let tracer = Traceroute()
        var hops: [TracerouteHop] = []
        var started = false
        var reached = false
        for await event in tracer.trace(host: "1.1.1.1",
                                        config: .init(maxHops: 20, probesPerHop: 3, timeout: 1.5, resolveNames: false)) {
            switch event {
            case .started(let ip, _):
                started = true
                XCTAssertEqual(ip, "1.1.1.1")
            case .hop(let hop):
                hops.append(hop)
            case .finished(let r):
                reached = r
            }
        }
        XCTAssertTrue(started)
        XCTAssertFalse(hops.isEmpty, "no hops recorded")
        // At least one intermediate or the destination must have answered.
        let responding = hops.filter { !$0.isTimeout }
        XCTAssertFalse(responding.isEmpty, "no hop responded")
        for hop in hops {
            let rtts = hop.probes.compactMap { $0.rttMillis }
            print("hop \(hop.ttl): \(hop.routerIP ?? "*") \(rtts.map { String(format: "%.1f", $0) }) dest=\(hop.reachedDestination)")
        }
        // Trace should reach 1.1.1.1 in a reasonable number of hops.
        XCTAssertTrue(reached || hops.contains { $0.routerIP == "1.1.1.1" }, "did not reach destination")
    }

    func testTraceHopOrdering() async throws {
        try requiresInternet()
        let tracer = Traceroute()
        var lastTTL = 0
        for await event in tracer.trace(host: "8.8.8.8",
                                        config: .init(maxHops: 15, probesPerHop: 2, timeout: 1.0, resolveNames: false)) {
            if case .hop(let hop) = event {
                XCTAssertEqual(hop.ttl, lastTTL + 1, "hops must be sequential")
                lastTTL = hop.ttl
            }
        }
        XCTAssertGreaterThan(lastTTL, 0)
    }
}
