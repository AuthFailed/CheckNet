import XCTest
@testable import NetworkKit

final class MTRNATTests: XCTestCase {
    func testMTRAccumulates() async throws {
        try requiresInternet()
        var lastTable: [MTRHop] = []
        var rounds = 0
        for await event in MTRSession().run(host: "1.1.1.1",
                                            config: .init(maxHops: 15, timeout: 1.0, interval: 0.2, maxRounds: 3, resolveNames: false)) {
            switch event {
            case .started(let ip): XCTAssertEqual(ip, "1.1.1.1")
            case .update(let hops, let round): lastTable = hops; rounds = round
            case .finished: break
            case .failed(let reason): XCTFail("MTR to 1.1.1.1 failed: \(reason)")
            }
        }
        XCTAssertGreaterThanOrEqual(rounds, 1)
        XCTAssertFalse(lastTable.isEmpty)
        // After multiple rounds the last hop should have been probed several times.
        let dest = lastTable.first { $0.reachedDestination }
        if let dest {
            XCTAssertGreaterThanOrEqual(dest.sent, 1)
            print("MTR dest hop \(dest.ttl): sent=\(dest.sent) recv=\(dest.received) avg=\(dest.average ?? -1) loss=\(dest.lossPercent)%")
        }
        for h in lastTable {
            print("  \(h.ttl) \(h.host ?? "*") sent=\(h.sent) recv=\(h.received) best=\(h.best ?? -1) avg=\(h.average ?? -1)")
        }
    }

    func testSTUNPublicIP() async throws {
        try requiresInternet()
        let addr = try await STUNClient().discover()
        print("public IP via STUN: \(addr.ip):\(addr.port)")
        // Should be a valid dotted quad, not a private address.
        XCTAssertEqual(addr.ip.split(separator: ".").count, 4)
        XCTAssertFalse(NATDetector.isPrivate(addr.ip), "STUN returned a private IP")
    }

    func testCGNATClassification() {
        XCTAssertTrue(NATDetector.isCGNAT("100.64.0.1"))
        XCTAssertTrue(NATDetector.isCGNAT("100.127.255.255"))
        XCTAssertFalse(NATDetector.isCGNAT("100.128.0.1"))
        XCTAssertFalse(NATDetector.isCGNAT("8.8.8.8"))
        XCTAssertTrue(NATDetector.isPrivate("192.168.1.1"))
        XCTAssertTrue(NATDetector.isPrivate("10.0.0.1"))
        XCTAssertTrue(NATDetector.isPrivate("172.20.1.1"))
        XCTAssertFalse(NATDetector.isPrivate("172.32.1.1"))
    }

    func testNATDetectRuns() async throws {
        try requiresInternet()
        let report = await NATDetector().detect()
        print("NAT type: \(report.natType.rawValue), local=\(report.localIP ?? "?"), public=\(report.publicIP ?? "?")")
        print("findings: \(report.findings)")
        XCTAssertFalse(report.findings.isEmpty)
    }
}
