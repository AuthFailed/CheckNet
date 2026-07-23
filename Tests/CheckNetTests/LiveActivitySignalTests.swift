import XCTest

/// The Live Activity "Стоп" button and the Focus filter both talk to the ping
/// loop / notifier through these shared flags, so the semantics are pinned here.
final class LiveActivitySignalTests: XCTestCase {

    private func makeDefaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "test.liveactivity.\(UUID().uuidString)"))
    }

    // MARK: Stop generation

    func testNoStopBeforeAnyPress() throws {
        let d = try makeDefaults()
        let baseline = LiveActivitySignal.generation(d)
        XCTAssertFalse(LiveActivitySignal.stopRequested(since: baseline, d))
    }

    func testStopAfterBaselineIsSeen() throws {
        let d = try makeDefaults()
        let baseline = LiveActivitySignal.generation(d)
        LiveActivitySignal.requestStop(d)
        XCTAssertTrue(LiveActivitySignal.stopRequested(since: baseline, d))
    }

    func testStaleStopFromPreviousRunIsIgnored() throws {
        let d = try makeDefaults()
        // A previous run's Stop press…
        LiveActivitySignal.requestStop(d)
        // …must not cancel the next run, which snapshots a fresh baseline.
        let baseline = LiveActivitySignal.generation(d)
        XCTAssertFalse(LiveActivitySignal.stopRequested(since: baseline, d))
        // But a new press during this run does.
        LiveActivitySignal.requestStop(d)
        XCTAssertTrue(LiveActivitySignal.stopRequested(since: baseline, d))
    }

    // MARK: Focus mute

    func testFocusMuteDefaultsOff() throws {
        let d = try makeDefaults()
        XCTAssertFalse(FocusMonitorState.isMuted(d))
    }

    func testFocusMuteRoundTrips() throws {
        let d = try makeDefaults()
        FocusMonitorState.setMuted(true, d)
        XCTAssertTrue(FocusMonitorState.isMuted(d))
        FocusMonitorState.setMuted(false, d)
        XCTAssertFalse(FocusMonitorState.isMuted(d))
    }
}
