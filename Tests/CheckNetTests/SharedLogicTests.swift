import XCTest

/// Small pure helpers extracted from the app layer so they can be tested without
/// a running UI: IP validation, launch-argument parsing, the schedule rule, and
/// CSV escaping.
final class SharedLogicTests: XCTestCase {

    // MARK: IPAddress

    func testIPv4Recognised() {
        for v in ["1.1.1.1", "192.168.0.1", "0.0.0.0", "255.255.255.255"] {
            XCTAssertTrue(IPAddress.isValid(v), v)
        }
    }

    func testIPv6Recognised() {
        for v in ["::1", "2001:db8::1", "fe80::1", "2a00:1fa2:345:7f7c::1"] {
            XCTAssertTrue(IPAddress.isValid(v), v)
        }
    }

    func testNonIPRejected() {
        for v in ["example.com", "256.1.1.1", "1.1.1", "1.1.1.1.1", "", " 1.1.1.1", "1.1.1.1 "] {
            XCTAssertFalse(IPAddress.isValid(v), v)
        }
    }

    // MARK: LaunchArguments

    func testFullLaunchArguments() {
        let parsed = LaunchArguments.parse(["CheckNet", "-openTool", "ping", "-host", "1.1.1.1", "-run"])
        XCTAssertEqual(parsed, .init(toolRawValue: "ping", host: "1.1.1.1", run: true))
    }

    func testLaunchArgumentsWithoutRunOrHost() {
        let parsed = LaunchArguments.parse(["-openTool", "dnsLookup"])
        XCTAssertEqual(parsed, .init(toolRawValue: "dnsLookup", host: nil, run: false))
    }

    func testLaunchArgumentsMissingTool() {
        XCTAssertNil(LaunchArguments.parse(["-host", "1.1.1.1", "-run"]))
        XCTAssertNil(LaunchArguments.parse(["-openTool"]))      // flag with no value
        XCTAssertNil(LaunchArguments.parse([]))
    }

    func testLaunchArgumentsHostFlagWithoutValue() {
        let parsed = LaunchArguments.parse(["-openTool", "ping", "-host"])
        XCTAssertEqual(parsed, .init(toolRawValue: "ping", host: nil, run: false))
    }

    // MARK: ScheduleRule

    private let epoch = Date(timeIntervalSince1970: 1_000_000)

    func testDisabledIsNeverDue() {
        XCTAssertFalse(ScheduleRule.isDue(isEnabled: false, lastRun: nil, intervalMinutes: 30, now: epoch))
    }

    func testNeverRunIsDue() {
        XCTAssertTrue(ScheduleRule.isDue(isEnabled: true, lastRun: nil, intervalMinutes: 30, now: epoch))
    }

    func testNotDueBeforeInterval() {
        let last = epoch.addingTimeInterval(-29 * 60)
        XCTAssertFalse(ScheduleRule.isDue(isEnabled: true, lastRun: last, intervalMinutes: 30, now: epoch))
    }

    func testDueAtExactInterval() {
        let last = epoch.addingTimeInterval(-30 * 60)
        XCTAssertTrue(ScheduleRule.isDue(isEnabled: true, lastRun: last, intervalMinutes: 30, now: epoch))
    }

    func testIntervalClampedToMinimum() {
        // interval 1 min is clamped up to the 5-minute floor.
        let after2 = epoch.addingTimeInterval(-2 * 60)
        let after6 = epoch.addingTimeInterval(-6 * 60)
        XCTAssertFalse(ScheduleRule.isDue(isEnabled: true, lastRun: after2, intervalMinutes: 1, now: epoch))
        XCTAssertTrue(ScheduleRule.isDue(isEnabled: true, lastRun: after6, intervalMinutes: 1, now: epoch))
    }

    // MARK: HistoryCSV

    func testCSVLeavesPlainFieldsUnquoted() {
        XCTAssertEqual(HistoryCSV.escape("ping"), "ping")
    }

    func testCSVQuotesCommas() {
        XCTAssertEqual(HistoryCSV.escape("a,b"), "\"a,b\"")
    }

    func testCSVDoublesQuotes() {
        XCTAssertEqual(HistoryCSV.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    func testCSVQuotesNewlines() {
        XCTAssertEqual(HistoryCSV.escape("line1\nline2"), "\"line1\nline2\"")
    }

    func testCSVDocumentEscapesDetailAndKeepsColumns() {
        let record = CheckRecord(tool: "dns", host: "a,b.example", timestamp: Date(timeIntervalSince1970: 0),
                                 latencyMillis: 12.34, lossPercent: nil, succeeded: true,
                                 detail: "found \"weird\", value", source: .manual)
        let doc = HistoryCSV.document([record])
        let lines = doc.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.first, "timestamp,tool,host,latency_ms,loss_pct,succeeded,detail"[...])
        XCTAssertTrue(doc.contains("\"a,b.example\""), doc)
        XCTAssertTrue(doc.contains("\"found \"\"weird\"\", value\""), doc)
        XCTAssertTrue(doc.contains("12.3"), doc)   // latency formatted
        // Every data line keeps 7 comma-separated columns (commas inside quotes
        // don't count as separators when parsed, but the header defines 7).
        XCTAssertEqual(lines.count, 2)
    }

    func testCSVEmptyOptionalFields() {
        let record = CheckRecord(tool: "ping", host: "1.1.1.1", timestamp: Date(timeIntervalSince1970: 0),
                                 latencyMillis: nil, lossPercent: nil, succeeded: false,
                                 detail: "нет ответа", source: .manual)
        let line = HistoryCSV.line(record, formatter: ISO8601DateFormatter())
        XCTAssertTrue(line.contains(",,"), line)   // empty latency and loss
        XCTAssertTrue(line.hasSuffix("false,нет ответа"), line)
    }
}
