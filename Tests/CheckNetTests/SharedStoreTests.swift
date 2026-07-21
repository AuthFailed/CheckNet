import XCTest

/// Concurrency tests for the shared history store.
///
/// `appendHistory` is a read-modify-write over one file that the app, an
/// out-of-process App Intent, the scheduler and the monitoring loop all reach.
/// Unsynchronised, concurrent writers overwrite each other: a two-process run of
/// 200 appends each kept 12 records out of 400 before the lock was added.
///
/// These tests cover contention inside one process. The cross-process half is
/// exercised by building `Shared/` into a small harness and running two copies
/// of it against one container — see the pull request for #11.
final class SharedStoreTests: XCTestCase {
    /// Whatever the host environment already had, restored afterwards so a test
    /// run never destroys a real history file.
    private var saved: [CheckRecord] = []

    override func setUp() {
        super.setUp()
        saved = SharedStore.history()
        SharedStore.clearHistory()
    }

    override func tearDown() {
        SharedStore.clearHistory()
        for record in saved.reversed() { SharedStore.appendHistory(record) }
        super.tearDown()
    }

    private func record(_ i: Int, tag: String = "t") -> CheckRecord {
        CheckRecord(tool: "test", host: "\(tag)-\(i)", timestamp: Date(),
                    latencyMillis: Double(i), lossPercent: 0,
                    succeeded: true, detail: "\(tag)/\(i)", source: .manual)
    }

    func testConcurrentAppendsKeepEveryRecord() {
        let count = 200
        DispatchQueue.concurrentPerform(iterations: count) { i in
            SharedStore.appendHistory(self.record(i))
        }

        let stored = SharedStore.history()
        XCTAssertEqual(stored.count, count, "records were lost to a concurrent write")
        XCTAssertEqual(Set(stored.map(\.id)).count, count, "duplicate ids in history")
        XCTAssertEqual(Set(stored.map(\.host)), Set((0..<count).map { "t-\($0)" }),
                       "a specific record went missing")
    }

    /// Deleting while other writers append must not roll the file back to a
    /// stale snapshot taken before their appends.
    func testConcurrentAppendAndDeleteDoNotLoseUnrelatedRecords() {
        let doomed = record(999, tag: "doomed")
        SharedStore.appendHistory(doomed)

        DispatchQueue.concurrentPerform(iterations: 100) { i in
            if i == 50 {
                SharedStore.deleteHistory(id: doomed.id)
            } else {
                SharedStore.appendHistory(self.record(i))
            }
        }

        let stored = SharedStore.history()
        XCTAssertFalse(stored.contains { $0.id == doomed.id }, "delete was lost")
        XCTAssertEqual(stored.count, 99, "appends were lost alongside the delete")
    }

    func testHistoryIsScopedBySource() {
        SharedStore.appendHistory(record(1))
        var scheduled = record(2)
        scheduled.source = .scheduled
        SharedStore.appendHistory(scheduled)

        XCTAssertEqual(SharedStore.history(source: .manual).count, 1)
        XCTAssertEqual(SharedStore.history(source: .scheduled).count, 1)

        SharedStore.clearHistory(source: .scheduled)
        XCTAssertEqual(SharedStore.history(source: .manual).count, 1)
        XCTAssertTrue(SharedStore.history(source: .scheduled).isEmpty)
    }
}
