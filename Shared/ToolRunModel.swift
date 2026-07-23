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

    /// Optional Live Activity for a one-shot run. Set it before `start()` and
    /// every tool on `ToolRunModel` shows a live status for free: a "running"
    /// state, then the result. `content` maps the current phase to what the
    /// Dynamic Island shows.
    struct ActivityDescriptor {
        var kind: CheckActivityKind
        var title: String
        var subtitle: String
        var content: (RunPhase<Value>) -> CheckActivityView
    }
    var activity: ActivityDescriptor?

    init() {}

    /// Fire-and-forget entry point for a SwiftUI button. A run already in flight
    /// is cancelled first, so double taps can't leave two operations racing.
    ///
    /// `onSuccess` runs on the main actor exactly once per successful completion
    /// — the place to record history or send a webhook. It fires per run, not per
    /// distinct value, so two runs with an identical result still report twice
    /// (which a view `.onChange(of:)` on the value would miss).
    func start(_ operation: @escaping @Sendable () async throws -> Value,
               onSuccess: (@MainActor @Sendable (Value) -> Void)? = nil) {
        cancel()
        task = Task { await self.perform(operation, onSuccess: onSuccess) }
    }

    /// The awaitable core: runs `operation` and records its outcome. Exposed so
    /// callers (and tests) can await completion.
    func perform(_ operation: @Sendable () async throws -> Value,
                 onSuccess: (@MainActor @Sendable (Value) -> Void)? = nil) async {
        phase = .running
        // A fresh controller per run, so overlapping runs never end each other's
        // activity. Nil descriptor (or macOS) makes every call a no-op.
        let controller = activity.map { _ in CheckActivityController() }
        if let activity, let controller {
            controller.start(kind: activity.kind, title: activity.title,
                             subtitle: activity.subtitle, view: activity.content(.running))
        }
        do {
            let result = try await operation()
            phase = .success(result)
            onSuccess?(result)
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failure(error.localizedDescription)
        }
        if let activity, let controller {
            // A one-shot result is worth keeping on the Lock Screen to glance at.
            await controller.end(activity.content(phase), lingerSeconds: 90)
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
