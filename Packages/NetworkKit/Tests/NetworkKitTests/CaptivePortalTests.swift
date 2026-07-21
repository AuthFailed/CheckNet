import XCTest
@testable import NetworkKit

final class CaptivePortalTests: XCTestCase {
    /// On a normal (non-captive) network, Apple's probe returns its Success page
    /// verbatim.
    func testOpenNetworkDetected() async {
        let result = await CaptivePortalCheck().run()
        print("captive: \(result.state.label) — \(result.detail)")
        XCTAssertEqual(result.state, .open, "this test network is not behind a captive portal")
        XCTAssertNil(result.redirectURL)
    }

    func testStatesAreLabelled() {
        XCTAssertFalse(CaptivePortalResult.State.open.label.isEmpty)
        XCTAssertFalse(CaptivePortalResult.State.captive.label.isEmpty)
        XCTAssertFalse(CaptivePortalResult.State.unknown.label.isEmpty)
    }
}
