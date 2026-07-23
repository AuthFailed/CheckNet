import Foundation

/// Serialises history records to CSV. The escaping lives here, in `Shared/`, so
/// it can be unit-tested directly — a stray quote or comma in a `detail` string
/// must not corrupt the exported file a user opens in a spreadsheet.
enum HistoryCSV {
    static let header = "timestamp,tool,host,latency_ms,loss_pct,succeeded,detail"

    /// RFC 4180 field escaping: wrap in quotes and double any internal quote when
    /// the field contains a comma, quote, or line break.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func line(_ r: CheckRecord, formatter: ISO8601DateFormatter) -> String {
        let latency = r.latencyMillis.map { String(format: "%.1f", $0) } ?? ""
        let loss = r.lossPercent.map { String(format: "%.1f", $0) } ?? ""
        return [
            formatter.string(from: r.timestamp),
            escape(r.tool),
            escape(r.host),
            latency,
            loss,
            String(r.succeeded),
            escape(r.detail)
        ].joined(separator: ",")
    }

    static func document(_ records: [CheckRecord]) -> String {
        var lines = [header]
        let formatter = ISO8601DateFormatter()
        for r in records { lines.append(line(r, formatter: formatter)) }
        return lines.joined(separator: "\n")
    }
}
