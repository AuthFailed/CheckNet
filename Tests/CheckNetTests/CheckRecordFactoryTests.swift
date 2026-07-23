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
        XCTAssertEqual(r.detail, "5/5, 0% потерь, avg 12 мс")
        XCTAssertEqual(r.kind, .manual)
    }

    func testPingAllLostOmitsAverage() {
        let r = CheckRecord.ping(host: "10.0.0.9", avg: nil, lossPercent: 100,
                                 received: 0, transmitted: 3)
        XCTAssertFalse(r.succeeded)
        XCTAssertEqual(r.detail, "0/3, 100% потерь")   // no "avg" tail when nothing came back
        XCTAssertNil(r.latencyMillis)
    }

    func testPingFailureRecord() {
        let r = CheckRecord.pingFailure(host: "bad.host", reason: "не удалось разрешить имя",
                                        source: .scheduled)
        XCTAssertEqual(r.tool, "ping")
        XCTAssertFalse(r.succeeded)
        XCTAssertEqual(r.detail, "ошибка: не удалось разрешить имя")
        XCTAssertEqual(r.kind, .scheduled)
    }

    func testBlockingRestrictedRecord() {
        let r = CheckRecord.blocking(checkID: "sniBlocking", host: "www.tor-project.org",
                                     headline: "Блокировка по SNI", restricted: true)
        XCTAssertEqual(r.tool, "blocking.sniBlocking")
        XCTAssertFalse(r.succeeded)
        XCTAssertEqual(r.detail, "Блокировка по SNI")
    }

    func testBlockingCleanRecordSucceeds() {
        let r = CheckRecord.blocking(checkID: "dnsSpoofing", host: "rutracker.org",
                                     headline: "Чисто", restricted: false, source: .scheduled)
        XCTAssertTrue(r.succeeded)
        XCTAssertEqual(r.kind, .scheduled)
    }
}
