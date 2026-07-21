import Foundation
import ActivityKit

/// A compact snapshot of the most recent check for a host — surfaced in
/// widgets, the Dynamic Island, and the app.
struct PingSnapshot: Codable, Hashable, Sendable {
    enum Status: String, Codable, Sendable { case ok, degraded, down, unknown }

    var host: String
    var ip: String
    var latencyMillis: Double?
    var lossPercent: Double
    var jitterMillis: Double?
    var status: Status
    var timestamp: Date

    static let placeholder = PingSnapshot(host: "1.1.1.1", ip: "1.1.1.1", latencyMillis: 12,
                                          lossPercent: 0, jitterMillis: 2, status: .ok, timestamp: Date())

    var statusLabel: String {
        switch status {
        case .ok: return "Онлайн"
        case .degraded: return "Нестабильно"
        case .down: return "Недоступен"
        case .unknown: return "—"
        }
    }

    static func status(loss: Double, latency: Double?) -> Status {
        if loss >= 100 { return .down }
        if loss > 0 || (latency ?? 0) > 200 { return .degraded }
        if latency != nil { return .ok }
        return .unknown
    }
}

/// Where a history record came from.
enum HistorySource: String, Codable, Sendable, Hashable {
    /// The user ran the test by hand.
    case manual
    /// A recurring schedule ran it. Kept in a separate history so it doesn't
    /// clutter the manual log.
    case scheduled
}

/// A single stored history record for a completed check.
struct CheckRecord: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var tool: String
    var host: String
    var timestamp: Date
    var latencyMillis: Double?
    var lossPercent: Double?
    var succeeded: Bool
    var detail: String
    /// Optional so records written before this field decode as `.manual`.
    var source: HistorySource?

    /// The record's source, defaulting to manual for legacy records.
    var kind: HistorySource { source ?? .manual }
}

/// ActivityKit attributes for a live ping session (Dynamic Island + Lock Screen).
struct PingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var latencyMillis: Double?
        var lossPercent: Double
        var received: Int
        var transmitted: Int
        var status: PingSnapshot.Status
        var isRunning: Bool
    }

    var host: String
    var ip: String
}
