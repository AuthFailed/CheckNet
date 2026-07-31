import XCTest

/// The ping/blocking history factories that replaced hand-built `CheckRecord`s
/// across the intents, scheduler and view models.
final class CheckRecordFactoryTests: XCTestCase {

    func testPingSuccessRecord() {
        let r = CheckRecord.ping(host: "1.1.1.1", avg: 12.4, lossPercent: 0,
                                 received: 5, transmitted: 5)
        XCTAssertEqual(r.tool, "ping")
        XCTAssertEqual(r.host, "1.1.1.1")
        XCTAssertEqual(r.latencyMillis, 12.4)
        XCTAssertEqual(r.lossPercent, 0)
        XCTAssertTrue(r.succeeded)
        XCTAssertEqual(r.detail, "5/5, 0% loss, avg 12 ms")
        XCTAssertEqual(r.kind, .manual)
    }

    func testPingAllLostOmitsAverage() {
        let r = CheckRecord.ping(host: "10.0.0.9", avg: nil, lossPercent: 100,
                                 received: 0, transmitted: 3)
        XCTAssertFalse(r.succeeded)
        XCTAssertEqual(r.detail, "0/3, 100% loss")   // no "avg" tail when nothing came back
        XCTAssertNil(r.latencyMillis)
    }

    func testPingFailureRecord() {
        let r = CheckRecord.pingFailure(host: "bad.host", reason: "couldn't resolve host",
                                        source: .scheduled)
        XCTAssertEqual(r.tool, "ping")
        XCTAssertFalse(r.succeeded)
        XCTAssertEqual(r.detail, "error: couldn't resolve host")
        XCTAssertEqual(r.kind, .scheduled)
    }

    func testBlockingRestrictedRecord() {
        let r = CheckRecord.blocking(checkID: "sniBlocking", host: "www.tor-project.org",
                                     headline: "SNI-based block", restricted: true)
        XCTAssertEqual(r.tool, "blocking.sniBlocking")
        XCTAssertFalse(r.succeeded)
        XCTAssertEqual(r.detail, "SNI-based block")
    }

    func testBlockingCleanRecordSucceeds() {
        let r = CheckRecord.blocking(checkID: "dnsSpoofing", host: "rutracker.org",
                                     headline: "Clean", restricted: false, source: .scheduled)
        XCTAssertTrue(r.succeeded)
        XCTAssertEqual(r.kind, .scheduled)
    }
}
