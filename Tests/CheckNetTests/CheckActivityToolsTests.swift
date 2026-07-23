import XCTest

/// Content builders for the newly Live-Activity-enabled tools (speed test,
/// bufferbloat, MTR, traceroute). Pure, so the Dynamic Island copy for each is
/// pinned without a device.
final class CheckActivityToolsTests: XCTestCase {

    // MARK: Speed test

    func testSpeedRunningShowsLiveMbps() {
        let v = SpeedActivityContent.view(liveMbps: 87.6, directionLabel: "Загрузка",
                                          download: nil, upload: nil, phaseLabel: "", isRunning: true)
        XCTAssertEqual(v.headline, "88 Мбит/с")
        XCTAssertEqual(v.caption, "Загрузка")           // falls back to direction when no phase
        XCTAssertEqual(v.status, .unknown)
    }

    func testSpeedPhaseLabelWinsOverDirection() {
        let v = SpeedActivityContent.view(liveMbps: 0, directionLabel: "Загрузка",
                                          download: nil, upload: nil,
                                          phaseLabel: "переключаюсь на HTTP-тест…", isRunning: true)
        XCTAssertEqual(v.caption, "переключаюсь на HTTP-тест…")
    }

    func testSpeedDoneShowsDownloadResult() {
        let v = SpeedActivityContent.view(liveMbps: 0, directionLabel: "Отдача",
                                          download: 120, upload: 40, phaseLabel: "", isRunning: false)
        XCTAssertEqual(v.headline, "120 Мбит/с")
        XCTAssertEqual(v.caption, "готово")
        XCTAssertEqual(v.status, .ok)
        XCTAssertEqual(v.stats.first { $0.label == "Отдача" }?.value, "40")
    }

    // MARK: Bufferbloat

    func testBufferbloatRunningShowsPhaseAndRTT() {
        let v = BufferbloatActivityContent.view(phaseLabel: "Загрузка", latestRTT: 43,
                                                gradeLetter: nil, addedLatency: nil,
                                                idleRTT: nil, loadedRTT: nil, isRunning: true)
        XCTAssertEqual(v.headline, "43 мс")
        XCTAssertEqual(v.caption, "Загрузка")
        XCTAssertEqual(v.status, .unknown)
    }

    func testBufferbloatDoneShowsGradeAndColour() {
        let v = BufferbloatActivityContent.view(phaseLabel: "", latestRTT: nil,
                                                gradeLetter: "C", addedLatency: 45,
                                                idleRTT: 20, loadedRTT: 65, isRunning: false)
        XCTAssertEqual(v.headline, "C")
        XCTAssertEqual(v.caption, "+45 мс под нагрузкой")
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
        XCTAssertEqual(v.headline, "24 мс")
        XCTAssertEqual(v.caption, "раунд 4")
        XCTAssertEqual(v.status, .ok)
        XCTAssertEqual(v.stats.first { $0.label == "Хопы" }?.value, "8")
    }

    func testMTRUnknownBeforeAnyHop() {
        let v = MTRActivityContent.view(host: "x", round: 0, hopCount: 0,
                                        lastLoss: 100, lastAvg: nil, isRunning: true)
        XCTAssertEqual(v.status, .unknown)
        XCTAssertEqual(v.headline, "0 хопов")
    }

    // MARK: Traceroute

    func testTracerouteRunning() {
        let v = TracerouteActivityContent.view(host: "cloudflare.com", hopCount: 5,
                                               reached: false, isRunning: true)
        XCTAssertEqual(v.headline, "5 хопов")
        XCTAssertEqual(v.caption, "идёт трассировка")
        XCTAssertEqual(v.status, .unknown)
    }

    func testTracerouteReached() {
        let v = TracerouteActivityContent.view(host: "cloudflare.com", hopCount: 9,
                                               reached: true, isRunning: false)
        XCTAssertEqual(v.caption, "цель достигнута")
        XCTAssertEqual(v.status, .ok)
    }
}
