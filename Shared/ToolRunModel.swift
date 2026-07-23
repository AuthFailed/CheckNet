import Foundation
import Observation

/// A reusable view model for the ~15 tool screens that each hand-roll the same
/// `isRunning / result / errorMessage / run() / cancel()` shape.
///
/// It owns a single `RunPhase`, captures thrown errors into `.failure`, and
/// treats cancellation as a return to idle rather than an error. The tool views
/// migrate onto it during the ToolScaffold rewrite (#15); introducing it here
/// first gives that pass a tested seam to build on and keeps history/webhook
/// side effects centralisable in one place.
@MainActor
@Observable
final class ToolRunModel<Value> {
    private(set) var phase: RunPhase<Value> = .idle
    private var task: Task<Void, Never>?

    var isRunning: Bool { phase.isRunning }
    var value: Value? { phase.value }
    var errorMessage: String? { phase.errorMessage }

    init() {}

    /// Fire-and-forget entry point for a SwiftUI button. A run already in flight
    /// is cancelled first, so double taps can't leave two operations racing.
    func start(_ operation: @escaping @Sendable () async throws -> Value) {
        cancel()
        task = Task { await self.perform(operation) }
    }

    /// The awaitable core: runs `operation` and records its outcome. Exposed so
    /// callers (and tests) can await completion.
    func perform(_ operation: @Sendable () async throws -> Value) async {
        phase = .running
        do {
            let result = try await operation()
            phase = .success(result)
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failure(error.localizedDescription)
        }
    }

    /// Cancels an in-flight run and returns to idle, leaving any prior
    /// success/failure result untouched if nothing is running.
    func cancel() {
        task?.cancel()
        task = nil
        if phase.isRunning { phase = .idle }
    }
}
