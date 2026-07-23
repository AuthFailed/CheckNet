import XCTest

/// The Live Activity content builders are the tool-agnostic core of the
/// generalized activity: producers map their data into a `CheckActivityView`
/// and the widget renders it. Pinned here so the copy and aggregation don't
/// have to be checked by eye in the Dynamic Island.
final class CheckActivityContentTests: XCTestCase {

    // MARK: Ping

    func testPingViewFormatsLatencyAndStats() {
        let v = PingActivityContent.view(latency: 12.4, loss: 0, received: 5, transmitted: 5,
                                         status: .ok, isRunning: true)
        XCTAssertEqual(v.headline, "12 мс")
        XCTAssertEqual(v.caption, "идёт проверка")
        XCTAssertEqual(v.status, .ok)
        XCTAssertEqual(v.stats.first { $0.label == "Пакеты" }?.value, "5/5")
        XCTAssertEqual(v.stats.first { $0.label == "Статус" }?.value, "OK")
    }

    func testPingViewWithoutLatencyShowsDash() {
        let v = PingActivityContent.view(latency: nil, loss: 100, received: 0, transmitted: 3,
                                         status: .down, isRunning: false)
        XCTAssertEqual(v.headline, "—")
        XCTAssertEqual(v.caption, "завершено")
    }

    // MARK: Monitor aggregation

    private func entries(_ statuses: [PingSnapshot.Status]) -> [MonitoredEntry] {
        statuses.enumerated().map { MonitoredEntry(host: "h\($0.offset)", status: $0.element) }
    }

    func testMonitorOverallIsWorstStatus() {
        XCTAssertEqual(MonitorActivityContent.overallStatus(entries([.ok, .down, .ok])), .down)
        XCTAssertEqual(MonitorActivityContent.overallStatus(entries([.ok, .degraded])), .degraded)
        XCTAssertEqual(MonitorActivityContent.overallStatus(entries([.ok, .ok])), .ok)
        XCTAssertEqual(MonitorActivityContent.overallStatus(entries([.unknown, .unknown])), .unknown)
    }

    func testMonitorHeadlineCountsOnline() {
        // 3 up (ok/degraded count as online), 1 down → "3/4".
        let v = MonitorActivityContent.view(for: entries([.ok, .degraded, .ok, .down]))
        XCTAssertEqual(v.headline, "3/4")
        XCTAssertEqual(v.caption, "не отвечают: 1")
        XCTAssertEqual(v.status, .down)
        XCTAssertEqual(v.stats.first { $0.label == "Не отвечают" }?.value, "1")
    }

    func testMonitorCaptionWhenAllUp() {
        let v = MonitorActivityContent.view(for: entries([.ok, .ok]))
        XCTAssertEqual(v.headline, "2/2")
        XCTAssertEqual(v.caption, "все отвечают")
    }

    func testMonitorCaptionBeforeFirstCheck() {
        let v = MonitorActivityContent.view(for: entries([.unknown, .unknown]))
        XCTAssertEqual(v.caption, "ожидание проверки")
        XCTAssertEqual(v.headline, "0/2")
    }

    func testMonitorEmptyState() {
        let v = MonitorActivityContent.view(for: [])
        XCTAssertEqual(v.caption, "нет хостов")
        XCTAssertEqual(v.headline, "0/0")
    }

    func testMonitorSubtitle() {
        XCTAssertEqual(MonitorActivityContent.subtitle(for: entries([.ok, .ok, .down])), "3 хостов")
    }
}
