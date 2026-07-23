import XCTest

/// The transition matrix decides when a background/foreground check fires a
/// push, so every edge is pinned here rather than discovered on a device.
final class MonitorNotificationTests: XCTestCase {
    typealias S = PingSnapshot.Status
    typealias T = MonitorNotification.Transition

    // MARK: Transition matrix

    func testGoingDownAlerts() {
        XCTAssertEqual(MonitorNotification.transition(from: .ok, to: .down), .down)
        XCTAssertEqual(MonitorNotification.transition(from: .degraded, to: .down), .down)
    }

    func testRecoveryAlerts() {
        XCTAssertEqual(MonitorNotification.transition(from: .down, to: .ok), .recovered)
        XCTAssertEqual(MonitorNotification.transition(from: .down, to: .degraded), .recovered)
    }

    func testFirstObservationNeverAlerts() {
        // A freshly added host starts .unknown; the first result must be silent.
        XCTAssertNil(MonitorNotification.transition(from: .unknown, to: .down))
        XCTAssertNil(MonitorNotification.transition(from: .unknown, to: .ok))
    }

    func testFlappingWithinUpBandIsSilent() {
        XCTAssertNil(MonitorNotification.transition(from: .ok, to: .degraded))
        XCTAssertNil(MonitorNotification.transition(from: .degraded, to: .ok))
    }

    func testNoChangeIsSilent() {
        XCTAssertNil(MonitorNotification.transition(from: .down, to: .down))
        XCTAssertNil(MonitorNotification.transition(from: .ok, to: .ok))
    }

    // MARK: Plan

    func testDownPlanIsTimeSensitiveAndNamesHost() {
        let plan = MonitorNotification.plan(host: "1.1.1.1", transition: .down)
        XCTAssertTrue(plan.timeSensitive)
        XCTAssertTrue(plan.title.contains("1.1.1.1"))
        XCTAssertEqual(plan.threadID, "1.1.1.1")
    }

    func testRecoveryPlanIsNotTimeSensitive() {
        let plan = MonitorNotification.plan(host: "example.com", transition: .recovered)
        XCTAssertFalse(plan.timeSensitive)
        XCTAssertEqual(plan.threadID, "example.com")
    }

    // MARK: Background cadence

    func testEarliestBeginDateClampsToSystemFloor() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // A 5-minute request is lifted to the 15-minute floor.
        XCTAssertEqual(BackgroundRefresh.earliestBeginDate(now: now, intervalMinutes: 5),
                       now.addingTimeInterval(15 * 60))
        // A longer interval is honoured as asked.
        XCTAssertEqual(BackgroundRefresh.earliestBeginDate(now: now, intervalMinutes: 30),
                       now.addingTimeInterval(30 * 60))
    }

    // MARK: MonitorStore round-trip

    func testMonitorStoreRoundTrips() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.monitor.\(UUID().uuidString)"))
        let entries = [
            MonitoredEntry(host: "1.1.1.1", status: .ok, lastLatency: 12, lastChecked: nil, lossPercent: 0),
            MonitoredEntry(host: "8.8.8.8", status: .down, lastLatency: nil, lastChecked: nil, lossPercent: 100)
        ]
        MonitorStore.save(entries, to: defaults)
        let loaded = MonitorStore.load(from: defaults)
        XCTAssertEqual(loaded.map(\.host), ["1.1.1.1", "8.8.8.8"])
        XCTAssertEqual(loaded.last?.status, .down)
    }

    func testMonitorStoreEmptyWhenAbsent() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.monitor.\(UUID().uuidString)"))
        XCTAssertTrue(MonitorStore.load(from: defaults).isEmpty)
    }
}
