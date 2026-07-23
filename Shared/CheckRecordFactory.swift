import Foundation

/// Factories for the history records that the ping and blocking call sites were
/// each assembling by hand — same `tool` naming, same Russian `detail` string,
/// copied across the intents, the scheduler and the view models with small
/// drifts. Centralising them keeps the stored format consistent.
///
/// They take primitives rather than NetworkKit's `PingStats`, so this stays in
/// `Shared/` (which links no NetworkKit) and remains unit-testable.
extension CheckRecord {

    /// A record for a completed ping measurement.
    static func ping(host: String, avg: Double?, lossPercent: Double,
                     received: Int, transmitted: Int,
                     source: HistorySource = .manual,
                     timestamp: Date = Date()) -> CheckRecord {
        var detail = "\(received)/\(transmitted), \(Int(lossPercent))% потерь"
        if received > 0, let avg {
            detail += ", avg \(String(format: "%.0f", avg)) мс"
        }
        return CheckRecord(
            tool: "ping", host: host, timestamp: timestamp,
            latencyMillis: avg, lossPercent: lossPercent,
            succeeded: received > 0, detail: detail, source: source
        )
    }

    /// A record for a ping that failed to run (resolution/socket error).
    static func pingFailure(host: String, reason: String,
                            source: HistorySource = .manual,
                            timestamp: Date = Date()) -> CheckRecord {
        CheckRecord(
            tool: "ping", host: host, timestamp: timestamp,
            latencyMillis: nil, lossPercent: nil,
            succeeded: false, detail: "ошибка: \(reason)", source: source
        )
    }

    /// A record for a blocking / censorship check verdict.
    static func blocking(checkID: String, host: String, headline: String,
                         restricted: Bool, source: HistorySource = .manual,
                         timestamp: Date = Date()) -> CheckRecord {
        CheckRecord(
            tool: "blocking.\(checkID)", host: host, timestamp: timestamp,
            latencyMillis: nil, lossPercent: nil,
            succeeded: !restricted, detail: headline, source: source
        )
    }
}
