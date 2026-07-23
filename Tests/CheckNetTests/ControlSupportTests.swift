import XCTest

/// The Control Center / Lock Screen controls build these URLs in one process
/// and the app parses them in another, so the grammar is pinned by tests.
final class ControlSupportTests: XCTestCase {

    // MARK: Tool links round-trip

    func testToolURLRoundTripsWithHostAndRun() throws {
        let url = try XCTUnwrap(ControlDeepLink.toolURL("ping", host: "1.1.1.1", run: true))
        XCTAssertEqual(ControlDeepLink.target(from: url),
                       .tool(raw: "ping", host: "1.1.1.1", run: true))
    }

    func testToolURLWithoutHostOrRun() throws {
        let url = try XCTUnwrap(ControlDeepLink.toolURL("dnsLookup"))
        XCTAssertEqual(ControlDeepLink.target(from: url),
                       .tool(raw: "dnsLookup", host: nil, run: false))
    }

    func testEmptyHostIsDroppedNotEmptyString() throws {
        let url = try XCTUnwrap(ControlDeepLink.toolURL("ping", host: "", run: false))
        XCTAssertEqual(ControlDeepLink.target(from: url),
                       .tool(raw: "ping", host: nil, run: false))
    }

    // MARK: Tab links

    func testTabURLRoundTrips() throws {
        let url = try XCTUnwrap(ControlDeepLink.tabURL("blocking"))
        XCTAssertEqual(ControlDeepLink.target(from: url), .tab("blocking"))
    }

    // MARK: Rejection

    func testForeignSchemeIsRejected() throws {
        let url = try XCTUnwrap(URL(string: "https://tool/ping"))
        XCTAssertNil(ControlDeepLink.target(from: url))
    }

    func testUnknownHostIsRejected() throws {
        let url = try XCTUnwrap(URL(string: "checknet://wat/ping"))
        XCTAssertNil(ControlDeepLink.target(from: url))
    }

    func testToolWithoutSegmentIsRejected() throws {
        let url = try XCTUnwrap(URL(string: "checknet://tool"))
        XCTAssertNil(ControlDeepLink.target(from: url))
    }

    // A host-sharing import link must not be mistaken for a control link.
    func testHostSharingLinkIsNotAControlTarget() throws {
        let hosts = [SavedHost(name: "R", value: "1.1.1.1", toolID: nil)]
        let url = try XCTUnwrap(HostSharing.url(for: hosts))
        XCTAssertNil(ControlDeepLink.target(from: url))
    }

    // MARK: Snapshot subtitle

    func testSubtitleShowsLatencyWhenOnline() {
        let snap = PingSnapshot(host: "1.1.1.1", ip: "1.1.1.1", latencyMillis: 11.6,
                                lossPercent: 0, jitterMillis: 1, status: .ok, timestamp: Date())
        XCTAssertEqual(ControlSnapshotDisplay.subtitle(snap), "12 мс")   // rounded
    }

    func testSubtitleShowsStatusWordWhenDown() {
        let snap = PingSnapshot(host: "x", ip: "", latencyMillis: nil,
                                lossPercent: 100, jitterMillis: nil, status: .down, timestamp: Date())
        XCTAssertEqual(ControlSnapshotDisplay.subtitle(snap), "Недоступен")
    }
}
