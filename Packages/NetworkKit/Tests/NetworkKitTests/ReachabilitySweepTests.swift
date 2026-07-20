import XCTest
@testable import NetworkKit

final class ReachabilitySweepTests: XCTestCase {
    // MARK: - Catalogue integrity

    func testCatalogueIsWellFormed() {
        let all = ProbeCatalog.all
        XCTAssertGreaterThan(all.count, 40)

        let ids = all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "target ids must be unique")

        for target in all {
            XCTAssertFalse(target.host.isEmpty)
            XCTAssertFalse(target.host.contains("/"), "\(target.id): host must be a bare hostname")
            XCTAssertTrue(target.host.contains("."), "\(target.id): host looks malformed")
        }

        // Every category must actually be populated, or the UI shows empty groups.
        for category in ProbeTarget.Category.allCases {
            XCTAssertFalse(ProbeCatalog.targets(in: category).isEmpty, "\(category) is empty")
        }

        // Domestic targets are the control arm — running the cutoff check against
        // them would be meaningless.
        XCTAssertTrue(ProbeCatalog.targets(in: .russianInfrastructure).allSatisfy(\.skipTransferCutoff))
        XCTAssertTrue(ProbeCatalog.targets(in: .foreignInfrastructure).allSatisfy { !$0.skipTransferCutoff })
    }

    func testGroupingByProvider() {
        let groups = ProbeCatalog.byProvider(in: .foreignInfrastructure)
        XCTAssertFalse(groups.isEmpty)
        let hetzner = groups.first { $0.provider == "Hetzner" }
        XCTAssertNotNil(hetzner)
        XCTAssertGreaterThan(hetzner?.targets.count ?? 0, 1, "Hetzner should have several vantage points")
        // Flattening the groups must lose nothing.
        let flattened = groups.flatMap(\.targets).count
        XCTAssertEqual(flattened, ProbeCatalog.targets(in: .foreignInfrastructure).count)
    }

    // MARK: - Live probes

    func testSingleTargetReachable() async {
        let target = ProbeCatalog.target(id: "SVC.GH")!
        let result = await ReachabilitySweep().check(target)
        print("github: \(result.status) — \(result.failure?.label ?? "ok") \(result.handshakeMillis.map { "\(Int($0)) ms" } ?? "")")
        XCTAssertEqual(result.status, .reachable)
        XCTAssertNotNil(result.resolvedIP)
    }

    /// APNs reachability is the whole point of the push category — if this can't
    /// be probed, the category is decoration.
    func testPushEndpointsProbe() async {
        let results = await ReachabilitySweep().run(category: .pushNotification)
        for r in results { print("push \(r.target.host): \(r.status.label)") }
        XCTAssertEqual(results.count, ProbeCatalog.targets(in: .pushNotification).count)
        XCTAssertTrue(results.contains { $0.target.id == "PUSH.APNS" && $0.status == .reachable },
                      "api.push.apple.com should be reachable from a clean network")
    }

    func testSweepPreservesOrderAndSummarises() async {
        let targets = Array(ProbeCatalog.targets(in: .russianInfrastructure).prefix(4))
        let sweep = ReachabilitySweep()
        let results = await sweep.run(targets: targets)

        XCTAssertEqual(results.map(\.id), targets.map(\.id), "results must come back in catalogue order")

        let summaries = sweep.summarise(results)
        XCTAssertEqual(summaries.count, Set(targets.map(\.provider)).count)
        XCTAssertEqual(summaries.reduce(0) { $0 + $1.total }, targets.count)
    }

    func testVerdictOnCleanNetwork() async {
        let sweep = ReachabilitySweep()
        let targets = Array(ProbeCatalog.targets(in: .foreignInfrastructure).prefix(6))
            + ProbeCatalog.targets(in: .russianInfrastructure)
        let results = await sweep.run(targets: targets)
        let finding = sweep.verdict(for: results)
        print("sweep verdict: \(finding.verdict) — \(finding.headline)")
        for line in finding.evidence { print("  · \(line)") }
        XCTAssertNotEqual(finding.verdict, .restricted, "a clean network should not report obstruction")
    }

    /// A host that simply doesn't exist must read as unavailable, never as
    /// interference — otherwise catalogue rot turns into fake censorship reports.
    func testDeadHostIsNotReportedAsObstruction() async {
        let dead = ProbeTarget(
            id: "TEST.DEAD", provider: "Test", country: nil,
            host: "no-such-host-checknet-test.invalid", category: .foreignInfrastructure
        )
        let result = await ReachabilitySweep().check(dead, timeout: 4)
        print("dead host: \(result.status) — \(result.failure?.label ?? "-")")
        XCTAssertEqual(result.status, .unavailable)
    }
}
