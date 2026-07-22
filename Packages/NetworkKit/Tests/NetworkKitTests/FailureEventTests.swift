import XCTest
@testable import NetworkKit

/// Every streaming engine must end a doomed run with a `.failed` event.
///
/// Ending the stream silently is what these engines used to do, and a stream
/// that stops before its first result is indistinguishable from one that found
/// nothing: the screen shows an empty list and the user reads it as "the
/// network is fine, there is just nothing here".
final class FailureEventTests: XCTestCase {
    /// A range the parser rejects. No network involved, so this one runs
    /// everywhere — including the blocking CI job.
    func testScannerReportsAnUnusableRange() async {
        var events: [ScanEvent] = []
        for await event in IPRangeScanner().scan(range: "not-an-ip") {
            events.append(event)
        }

        guard case .failed(let reason)? = events.last else {
            return XCTFail("expected a terminal .failed, got \(events)")
        }
        XCTAssertTrue(reason.contains("not-an-ip"), "the reason should name the range: \(reason)")
        XCTAssertFalse(
            events.contains { if case .finished = $0 { return true } else { return false } },
            "a rejected range must not also report a finished scan"
        )
    }

    /// The browser runs the same sweep, so an unusable range has to travel out
    /// of it rather than turn into "0 devices".
    func testBrowserForwardsTheScannerFailure() async {
        var events: [BrowserEvent] = []
        for await event in NetworkBrowser().browse(cidr: "not-an-ip") {
            events.append(event)
        }

        guard case .failed? = events.last else {
            return XCTFail("expected a terminal .failed, got \(events)")
        }
    }

    func testTracerouteReportsAnUnresolvableHost() async throws {
        try requiresInternet()
        var events: [TracerouteEvent] = []
        for await event in Traceroute().trace(host: "nosuchhost.invalid") {
            events.append(event)
        }

        guard case .failed(let reason)? = events.last else {
            return XCTFail("expected a terminal .failed, got \(events)")
        }
        XCTAssertFalse(reason.isEmpty)
        XCTAssertTrue(
            events.allSatisfy { if case .hop = $0 { return false } else { return true } },
            "a host that never resolved cannot have produced hops"
        )
    }

    func testMTRReportsAnUnresolvableHost() async throws {
        try requiresInternet()
        var events: [MTREvent] = []
        for await event in MTRSession().run(host: "nosuchhost.invalid", config: MTRConfig(maxHops: 3)) {
            events.append(event)
        }

        guard case .failed(let reason)? = events.last else {
            return XCTFail("expected a terminal .failed, got \(events)")
        }
        XCTAssertFalse(reason.isEmpty)
    }
}
