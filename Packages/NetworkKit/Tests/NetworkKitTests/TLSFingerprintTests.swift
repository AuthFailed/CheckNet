import XCTest
@testable import NetworkKit

final class TLSFingerprintTests: XCTestCase {
    /// Every profile must complete a handshake against a normal host. A profile
    /// that can't connect anywhere would report "обрыв" on every network and be
    /// worse than useless.
    func testEveryFingerprintCompletesHandshake() async {
        for fingerprint in TLSFingerprint.allCases {
            let sweep = ReachabilitySweep(fingerprint: fingerprint)
            let result = await sweep.check(ProbeCatalog.target(id: "SVC.GH")!)
            print("\(fingerprint.rawValue): \(result.status.label) \(result.handshakeMillis.map { "\(Int($0)) ms" } ?? (result.failure?.label ?? ""))")
            XCTAssertEqual(result.status, .reachable,
                           "fingerprint \(fingerprint.rawValue) failed to connect — the profile itself is broken")
        }
    }

    func testFingerprintsAreDistinctAndLabelled() {
        let all = TLSFingerprint.allCases
        XCTAssertEqual(Set(all.map(\.rawValue)).count, all.count)
        XCTAssertEqual(Set(all.map(\.label)).count, all.count, "labels must be distinguishable in a picker")
        for fingerprint in all {
            XCTAssertFalse(fingerprint.label.isEmpty)
            XCTAssertFalse(fingerprint.detail.isEmpty)
        }
        XCTAssertTrue(TLSFingerprint.noALPN.alpnProtocols.isEmpty)
        XCTAssertFalse(TLSFingerprint.system.alpnProtocols.isEmpty)
    }

    /// The cutoff check must accept a profile too — fingerprint-conditional
    /// filtering is exactly what this lets a user test for.
    func testCutoffCheckHonoursFingerprint() async {
        let probe = await TransferCutoffCheck(fingerprint: .tls12).probeSingleSegment(host: "cloudflare.com")
        print("cutoff over TLS 1.2: \(probe.outcome) — \(probe.detail)")
        XCTAssertEqual(probe.outcome, .passed)
    }

    // MARK: - National resolvers

    func testNationalResolversArePresent() {
        let national = DNSResolverInfo.presets(in: .national)
        XCTAssertEqual(national.count, 2)
        XCTAssertTrue(national.contains { $0.address == "195.208.4.1" }, "НСДИ primary missing")
        XCTAssertTrue(national.contains { $0.address == "62.76.76.62" }, "MSK-IX primary missing")
        XCTAssertTrue(national.allSatisfy { $0.secondary != nil }, "national resolvers publish a secondary")

        XCTAssertFalse(DNSResolverInfo.presets(in: .russian).isEmpty)
        XCTAssertFalse(DNSResolverInfo.presets(in: .foreign).isEmpty)
        // Addresses double as ids, so duplicates would collapse rows in a list.
        let ids = DNSResolverInfo.presets.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
