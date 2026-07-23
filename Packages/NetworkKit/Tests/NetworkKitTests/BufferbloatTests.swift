import XCTest
@testable import NetworkKit

final class BufferbloatTests: XCTestCase {

    // MARK: Grading (deterministic)

    func testGradeThresholds() {
        XCTAssertEqual(BufferbloatGrade.grade(addedLatencyMillis: 0), .a)
        XCTAssertEqual(BufferbloatGrade.grade(addedLatencyMillis: 4.9), .a)
        XCTAssertEqual(BufferbloatGrade.grade(addedLatencyMillis: 5), .b)
        XCTAssertEqual(BufferbloatGrade.grade(addedLatencyMillis: 29.9), .b)
        XCTAssertEqual(BufferbloatGrade.grade(addedLatencyMillis: 30), .c)
        XCTAssertEqual(BufferbloatGrade.grade(addedLatencyMillis: 99.9), .c)
        XCTAssertEqual(BufferbloatGrade.grade(addedLatencyMillis: 100), .d)
        XCTAssertEqual(BufferbloatGrade.grade(addedLatencyMillis: 399.9), .d)
        XCTAssertEqual(BufferbloatGrade.grade(addedLatencyMillis: 400), .f)
        XCTAssertEqual(BufferbloatGrade.grade(addedLatencyMillis: 5000), .f)
        XCTAssertEqual(BufferbloatGrade.f.letter, "F")
    }

    // MARK: Median / jitter

    func testMedian() {
        XCTAssertEqual(BufferbloatTest.median([]), 0)
        XCTAssertEqual(BufferbloatTest.median([42]), 42)
        XCTAssertEqual(BufferbloatTest.median([20, 21, 22]), 21)          // odd
        XCTAssertEqual(BufferbloatTest.median([40, 45]), 42.5)            // even
        XCTAssertEqual(BufferbloatTest.median([30, 10, 20]), 20)         // unsorted
    }

    func testJitter() {
        XCTAssertEqual(BufferbloatTest.jitter([10]), 0)
        XCTAssertEqual(BufferbloatTest.jitter([10, 14, 12]), 3)           // (4 + 2) / 2
    }

    // MARK: Summary (pure)

    func testSummariseComputesAddedLatencyAndGrade() {
        let r = BufferbloatTest.summarise(
            idle: [20, 22, 21], download: [120, 130, 125], upload: [40, 45],
            downloadMbps: 300, uploadMbps: 50, samples: []
        )
        XCTAssertEqual(r.idleRTT, 21)
        XCTAssertEqual(r.downloadRTT, 125)
        XCTAssertEqual(r.uploadRTT, 42.5)
        XCTAssertEqual(r.addedLatency, 104, accuracy: 0.001)   // 125 − 21
        XCTAssertEqual(r.grade, .d)
        XCTAssertEqual(r.downloadMbps, 300)
    }

    func testSummariseCleanLinkGradesA() {
        let r = BufferbloatTest.summarise(
            idle: [18, 19, 20], download: [20, 21, 22], upload: [19, 20],
            downloadMbps: 900, uploadMbps: 900, samples: []
        )
        XCTAssertLessThan(r.addedLatency, 5)
        XCTAssertEqual(r.grade, .a)
    }

    func testSummariseNoRepliesUnderLoadGradesF() {
        // Every probe timed out while saturated → worst case, not "no data".
        let r = BufferbloatTest.summarise(
            idle: [25], download: [], upload: [],
            downloadMbps: nil, uploadMbps: nil, samples: []
        )
        XCTAssertGreaterThanOrEqual(r.addedLatency, 400)
        XCTAssertEqual(r.grade, .f)
    }

    func testAddedLatencyNeverNegative() {
        // Loaded RTT below idle (noise) must clamp to 0, not go negative.
        let r = BufferbloatTest.summarise(
            idle: [50], download: [30], upload: [35],
            downloadMbps: 100, uploadMbps: 100, samples: []
        )
        XCTAssertEqual(r.addedLatency, 0)
        XCTAssertEqual(r.grade, .a)
    }

    // MARK: End-to-end (network)

    func testBufferbloatAgainstRealNetwork() async throws {
        try requiresInternet()
        // Short config to keep the test quick; real screens use the defaults.
        let config = BufferbloatTest.Config(idleSeconds: 1.5, loadSeconds: 2.5, pingInterval: 0.2)
        var phases: Set<BufferbloatPhase> = []
        var result: BufferbloatResult?
        var failure: String?

        for await event in BufferbloatTest().run(config: config) {
            switch event {
            case .phase(let p): phases.insert(p)
            case .sample: break
            case .finished(let r): result = r
            case .failed(let reason): failure = reason
            }
        }

        if let failure {
            throw XCTSkip("bufferbloat probe could not reach the ping host: \(failure)")
        }
        let r = try XCTUnwrap(result, "no finished result")
        XCTAssertEqual(phases, [.idle, .download, .upload], "all three phases should run")
        XCTAssertGreaterThan(r.idleRTT, 0, "idle RTT must be measured")
        XCTAssertGreaterThanOrEqual(r.addedLatency, 0)
        XCTAssertTrue(BufferbloatGrade.allCases.contains(r.grade))
        XCTAssertFalse(r.samples.isEmpty, "graph samples should be collected")
        print("bufferbloat: idle \(Int(r.idleRTT))ms  down \(Int(r.downloadRTT))ms  up \(Int(r.uploadRTT))ms  +\(Int(r.addedLatency))ms  grade \(r.grade.letter)  ↓\(r.downloadMbps.map { Int($0) } ?? 0)/↑\(r.uploadMbps.map { Int($0) } ?? 0) Mbps")
    }
}
