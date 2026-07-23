import XCTest

/// The reusable run-phase model that the tool screens adopt in #15.
@MainActor
final class ToolRunModelTests: XCTestCase {

    private struct Boom: LocalizedError {
        var errorDescription: String? { "что-то сломалось" }
    }

    func testStartsIdle() {
        let model = ToolRunModel<Int>()
        XCTAssertTrue(model.phase.isIdle)
        XCTAssertFalse(model.isRunning)
        XCTAssertNil(model.value)
        XCTAssertNil(model.errorMessage)
    }

    func testSuccessCapturesValue() async {
        let model = ToolRunModel<Int>()
        await model.perform { 42 }
        XCTAssertEqual(model.phase, .success(42))
        XCTAssertEqual(model.value, 42)
        XCTAssertFalse(model.isRunning)
        XCTAssertNil(model.errorMessage)
    }

    func testFailureCapturesLocalizedMessage() async {
        let model = ToolRunModel<Int>()
        await model.perform { throw Boom() }
        XCTAssertEqual(model.phase, .failure("что-то сломалось"))
        XCTAssertEqual(model.errorMessage, "что-то сломалось")
        XCTAssertNil(model.value)
    }

    func testCancellationErrorReturnsToIdle() async {
        let model = ToolRunModel<Int>()
        await model.perform { throw CancellationError() }
        XCTAssertTrue(model.phase.isIdle)
        XCTAssertNil(model.errorMessage)
    }

    func testRerunReplacesPreviousResult() async {
        let model = ToolRunModel<Int>()
        await model.perform { 1 }
        XCTAssertEqual(model.value, 1)
        await model.perform { throw Boom() }
        XCTAssertNil(model.value)
        XCTAssertEqual(model.errorMessage, "что-то сломалось")
        await model.perform { 2 }
        XCTAssertEqual(model.value, 2)
        XCTAssertNil(model.errorMessage)
    }

    func testCancelIdleKeepsPriorResult() async {
        let model = ToolRunModel<Int>()
        await model.perform { 7 }
        model.cancel()   // nothing running → prior success is retained
        XCTAssertEqual(model.value, 7)
    }

    func testOnSuccessFiresOncePerRun() async {
        let model = ToolRunModel<Int>()
        var received: [Int] = []
        await model.perform { 1 } onSuccess: { received.append($0) }
        await model.perform { 1 } onSuccess: { received.append($0) }   // same value, runs again
        XCTAssertEqual(received, [1, 1])   // fires per run, not per distinct value
    }

    func testOnSuccessSkippedOnFailure() async {
        let model = ToolRunModel<Int>()
        var fired = false
        await model.perform { throw Boom() } onSuccess: { _ in fired = true }
        XCTAssertFalse(fired)
    }

    func testOnSuccessSkippedOnCancellation() async {
        let model = ToolRunModel<Int>()
        var fired = false
        await model.perform { throw CancellationError() } onSuccess: { _ in fired = true }
        XCTAssertFalse(fired)
    }

    func testStartThenAwaitCompletes() async {
        let model = ToolRunModel<String>()
        model.start { "готово" }
        // Poll for the detached task to settle (it may not have begun yet).
        for _ in 0..<200 {
            if model.value != nil || model.errorMessage != nil { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(model.value, "готово")
    }
}
