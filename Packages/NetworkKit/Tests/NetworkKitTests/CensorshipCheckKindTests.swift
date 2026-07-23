import XCTest
@testable import NetworkKit

/// The dispatch table for `CensorshipCheckKind` — deterministic, no network.
/// Guards that every case is reachable, keeps a stable raw value (raw values are
/// persisted in scheduled tasks and history), and resolves a default target.
final class CensorshipCheckKindTests: XCTestCase {

    func testAllCasesHaveStableRawValues() {
        XCTAssertEqual(
            Set(CensorshipCheckKind.allCases.map(\.rawValue)),
            ["dnsSpoofing", "httpBlock", "sniBlocking", "ipBlocking", "whitelist", "siberian", "transferCutoff"]
        )
    }

    func testRawValueRoundTrips() {
        for kind in CensorshipCheckKind.allCases {
            XCTAssertEqual(CensorshipCheckKind(rawValue: kind.rawValue), kind)
        }
    }

    func testUnknownRawValueIsNil() {
        XCTAssertNil(CensorshipCheckKind(rawValue: "nope"))
    }

    func testNeedsTargetOnlyWhitelistExempt() {
        for kind in CensorshipCheckKind.allCases {
            XCTAssertEqual(kind.needsTarget, kind != .whitelist, "\(kind)")
        }
    }

    func testDefaultTargets() {
        XCTAssertEqual(CensorshipCheckKind.dnsSpoofing.defaultTarget, "rutracker.org")
        XCTAssertEqual(CensorshipCheckKind.httpBlock.defaultTarget, "rutracker.org")
        XCTAssertEqual(CensorshipCheckKind.sniBlocking.defaultTarget, "www.tor-project.org")
        XCTAssertEqual(CensorshipCheckKind.siberian.defaultTarget, "www.tor-project.org")
        XCTAssertEqual(CensorshipCheckKind.ipBlocking.defaultTarget, "x.com")
        XCTAssertEqual(CensorshipCheckKind.whitelist.defaultTarget, "")
        XCTAssertEqual(CensorshipCheckKind.transferCutoff.defaultTarget, TransferCutoffCheck.defaultTarget)
    }

    func testEveryTargetedCheckHasANonEmptyDefault() {
        for kind in CensorshipCheckKind.allCases where kind.needsTarget {
            XCTAssertFalse(kind.defaultTarget.isEmpty, "\(kind) needs a target but has no default")
        }
    }

    /// Real dispatch: a DNS-spoofing probe against its default target returns a
    /// finding with a valid verdict. Network-gated (informational in CI).
    func testDNSSpoofingDispatchReturnsFinding() async throws {
        try requiresInternet()
        let finding = await CensorshipCheckKind.dnsSpoofing.run(target: CensorshipCheckKind.dnsSpoofing.defaultTarget)
        XCTAssertTrue([.clean, .restricted, .inconclusive].contains(finding.verdict))
        XCTAssertFalse(finding.headline.isEmpty)
    }
}
