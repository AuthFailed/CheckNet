import XCTest

/// Content builders for the newly Live-Activity-enabled tools (speed test,
/// bufferbloat, MTR, traceroute). Pure, so the Dynamic Island copy for each is
/// pinned without a device.
final class CheckActivityToolsTests: XCTestCase {

    // MARK: Speed test

    func testSpeedRunningShowsLiveMbps() {
        let v = SpeedActivityContent.view(liveMbps: 87.6, directionLabel: "Download",
                                          download: nil, upload: nil, phaseLabel: "", isRunning: true)
        XCTAssertEqual(v.headline, "88 Mbps")
        XCTAssertEqual(v.caption, "Download")           // falls back to direction when no phase
        XCTAssertEqual(v.status, .unknown)
    }

    func testSpeedPhaseLabelWinsOverDirection() {
        let v = SpeedActivityContent.view(liveMbps: 0, directionLabel: "Download",
                                          download: nil, upload: nil,
                                          phaseLabel: "switching to HTTP test…", isRunning: true)
        XCTAssertEqual(v.caption, "switching to HTTP test…")
    }

    func testSpeedDoneShowsDownloadResult() {
        let v = SpeedActivityContent.view(liveMbps: 0, directionLabel: "Upload",
                                          download: 120, upload: 40, phaseLabel: "", isRunning: false)
        XCTAssertEqual(v.headline, "120 Mbps")
        XCTAssertEqual(v.caption, "done")
        XCTAssertEqual(v.status, .ok)
        XCTAssertEqual(v.stats.first { $0.label == "Upload" }?.value, "40")
    }

    // MARK: Bufferbloat

    func testBufferbloatRunningShowsPhaseAndRTT() {
        let v = BufferbloatActivityContent.view(phaseLabel: "Download", latestRTT: 43,
                                                gradeLetter: nil, addedLatency: nil,
                                                idleRTT: nil, loadedRTT: nil, isRunning: true)
        XCTAssertEqual(v.headline, "43 ms")
        XCTAssertEqual(v.caption, "Download")
        XCTAssertEqual(v.status, .unknown)
    }

    func testBufferbloatDoneShowsGradeAndColour() {
        let v = BufferbloatActivityContent.view(phaseLabel: "", latestRTT: nil,
                                                gradeLetter: "C", addedLatency: 45,
                                                idleRTT: 20, loadedRTT: 65, isRunning: false)
        XCTAssertEqual(v.headline, "C")
        XCTAssertEqual(v.caption, "+45 ms under load")
        XCTAssertEqual(v.status, .degraded)             // C → shaky
    }

    func testBufferbloatGradeColourMapping() {
        XCTAssertEqual(BufferbloatActivityContent.status(gradeLetter: "A"), .ok)
        XCTAssertEqual(BufferbloatActivityContent.status(gradeLetter: "D"), .down)
        XCTAssertEqual(BufferbloatActivityContent.status(gradeLetter: "F"), .down)
        XCTAssertEqual(BufferbloatActivityContent.status(gradeLetter: nil), .unknown)
    }

    // MARK: MTR

    func testMTRUsesDestinationLatencyAndLoss() {
        let v = MTRActivityContent.view(host: "cloudflare.com", round: 4, hopCount: 8,
                                        lastLoss: 0, lastAvg: 23.7, isRunning: true)
        XCTAssertEqual(v.headline, "24 ms")
        XCTAssertEqual(v.caption, "round 4")
        XCTAssertEqual(v.status, .ok)
        XCTAssertEqual(v.stats.first { $0.label == "Hops" }?.value, "8")
    }

    func testMTRUnknownBeforeAnyHop() {
        let v = MTRActivityContent.view(host: "x", round: 0, hopCount: 0,
                                        lastLoss: 100, lastAvg: nil, isRunning: true)
        XCTAssertEqual(v.status, .unknown)
        XCTAssertEqual(v.headline, "0 hops")
    }

    // MARK: Traceroute

    func testTracerouteRunning() {
        let v = TracerouteActivityContent.view(host: "cloudflare.com", hopCount: 5,
                                               reached: false, isRunning: true)
        XCTAssertEqual(v.headline, "5 hops")
        XCTAssertEqual(v.caption, "tracing")
        XCTAssertEqual(v.status, .unknown)
    }

    func testTracerouteReached() {
        let v = TracerouteActivityContent.view(host: "cloudflare.com", hopCount: 9,
                                               reached: true, isRunning: false)
        XCTAssertEqual(v.caption, "target reached")
        XCTAssertEqual(v.status, .ok)
    }

    // MARK: Scanners

    func testScanRunningShowsProgress() {
        let v = ScanActivityContent.view(foundLabel: "Open", found: 2,
                                         scanned: 40, total: 100, isRunning: true)
        XCTAssertEqual(v.headline, "40/100")
        XCTAssertEqual(v.caption, "scanning")
        XCTAssertEqual(v.status, .unknown)
        XCTAssertEqual(v.stats.first { $0.label == "Open" }?.value, "2")
    }

    func testScanDoneSummarisesFindings() {
        let v = ScanActivityContent.view(foundLabel: "Alive", found: 5,
                                         scanned: 254, total: 254, isRunning: false)
        XCTAssertEqual(v.headline, "254/254")
        XCTAssertEqual(v.caption, "done — 5 alive")
        XCTAssertEqual(v.status, .ok)
    }

    // MARK: Generic one-shot lookup (ToolRunModel seam)

    func testLookupRunningShowsTarget() {
        let v = LookupActivityContent.view(RunPhase<Int>.running, running: "example.com") { _ in ("x", "y") }
        XCTAssertEqual(v.headline, "example.com")
        XCTAssertEqual(v.caption, "running")
        XCTAssertTrue(v.isRunning)
    }

    func testLookupSuccessUsesDescribeAndStatus() {
        let v = LookupActivityContent.view(RunPhase.success(42), running: "q",
                                           status: { $0 > 0 ? .down : .ok }) { n in
            ("value \(n)", "done")
        }
        XCTAssertEqual(v.headline, "value 42")
        XCTAssertEqual(v.status, .down)          // status closure honoured
        XCTAssertFalse(v.isRunning)
    }

    func testLookupFailureIsUniform() {
        let v = LookupActivityContent.view(RunPhase<Int>.failure("boom"), running: "q") { _ in ("x", "y") }
        XCTAssertEqual(v.headline, "Error")
        XCTAssertEqual(v.caption, "boom")
        XCTAssertEqual(v.status, .down)
    }
}
