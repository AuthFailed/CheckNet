import Foundation

/// The lifecycle of a single tool run: idle → running → success/failure.
///
/// Every tool screen currently reimplements this as a trio of
/// `isRunning` / `result` / `errorMessage` flags that can drift out of sync
/// (e.g. an error left set while a new run is in flight). Modelling it as one
/// value makes the illegal states unrepresentable. `ToolRunModel` drives it;
/// the tool views adopt it in the ToolScaffold pass (#15).
enum RunPhase<Value> {
    case idle
    case running
    case success(Value)
    case failure(String)

    var isIdle: Bool { if case .idle = self { true } else { false } }
    var isRunning: Bool { if case .running = self { true } else { false } }

    /// The successful result, if the run finished successfully.
    var value: Value? {
        if case .success(let value) = self { value } else { nil }
    }

    /// The failure message, if the run failed.
    var errorMessage: String? {
        if case .failure(let message) = self { message } else { nil }
    }
}

extension RunPhase: Equatable where Value: Equatable {}
extension RunPhase: Sendable where Value: Sendable {}
