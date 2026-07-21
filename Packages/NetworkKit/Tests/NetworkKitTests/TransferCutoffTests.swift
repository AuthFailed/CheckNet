import XCTest
import Network
@testable import NetworkKit

final class TransferCutoffTests: XCTestCase {
    // MARK: - Failure classification

    func testFailureClassification() {
        XCTAssertEqual(ProbeFailureKind.classify(NWError.posix(.ECONNRESET)), .reset)
        XCTAssertEqual(ProbeFailureKind.classify(NWError.posix(.ECONNREFUSED)), .refused)
        XCTAssertEqual(ProbeFailureKind.classify(NWError.posix(.ETIMEDOUT)), .timeout)
        XCTAssertEqual(ProbeFailureKind.classify(NWError.posix(.EHOSTUNREACH)), .unreachable)
        XCTAssertEqual(ProbeFailureKind.classify(NetworkError.timedOut), .timeout)

        // A server-side TLS alert must never read as interference — that
        // distinction is the whole point of the classifier.
        XCTAssertFalse(ProbeFailureKind.tlsAlert.suggestsInterference)
        XCTAssertFalse(ProbeFailureKind.refused.suggestsInterference)
        XCTAssertTrue(ProbeFailureKind.reset.suggestsInterference)
        XCTAssertTrue(ProbeFailureKind.timeout.suggestsInterference)
    }

    // MARK: - Individual probes against real hosts

    func testSingleSegmentReaches() async throws {
        try requiresInternet()
        let probe = await TransferCutoffCheck().probeSingleSegment(host: TransferCutoffCheck.defaultTarget)
        print("single segment: \(probe.outcome) — \(probe.detail)")
        XCTAssertEqual(probe.outcome, .passed, "one-segment request should reach an uncensored network")
        XCTAssertEqual(probe.segmentsSent, 1)
    }

    /// The decisive arm. On a clean network the same bytes split across ~30
    /// packets must also arrive — if this freezes here, the probe itself is
    /// broken rather than the network being filtered.
    func testPacketCountReachesOnCleanNetwork() async throws {
        try requiresInternet()
        let probe = await TransferCutoffCheck().probePacketCount(host: TransferCutoffCheck.defaultTarget)
        print("packet count: \(probe.outcome) — \(probe.detail) [\(probe.segmentsSent) segments]")
        XCTAssertEqual(probe.outcome, .passed)
        XCTAssertGreaterThan(probe.segmentsSent, 10, "request should have been split into many packets")
    }

    func testByteAccumulationReachesOnCleanNetwork() async throws {
        try requiresInternet()
        let probe = await TransferCutoffCheck().probeByteAccumulation(host: TransferCutoffCheck.defaultTarget)
        print("byte accumulation: \(probe.outcome) — \(probe.detail) [\(probe.bytesSent) bytes]")
        XCTAssertEqual(probe.outcome, .passed)
        XCTAssertGreaterThan(probe.bytesSent, 40_000, "should have pushed past the 16-20 KB range")
    }

    // MARK: - Full check

    func testFullCheckOnCleanNetwork() async throws {
        try requiresInternet()
        let finding = await TransferCutoffCheck().run()
        print("cutoff verdict: \(finding.verdict) — \(finding.headline)")
        for line in finding.evidence { print("  · \(line)") }
        XCTAssertEqual(finding.verdict, .clean, "an uncensored network should not show a transfer cutoff")
    }

    /// A host that refuses us must read as `failed`, never as a freeze —
    /// otherwise every unreachable server would be reported as censorship.
    func testRefusedConnectionIsNotReportedAsFreeze() async throws {
        try requiresInternet()
        // Port 9 (discard) is closed on Cloudflare's edge.
        let probe = await TransferCutoffCheck().probeSingleSegment(host: TransferCutoffCheck.defaultTarget, port: 9, readTimeout: 3)
        print("closed port: \(probe.outcome) — \(probe.detail)")
        XCTAssertEqual(probe.outcome, .failed)
    }
}
