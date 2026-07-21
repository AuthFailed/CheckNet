import Foundation

/// Reads and writes shared state (last snapshots, monitored hosts, history)
/// used across the app, App Intents and Live Activities.
enum SharedStore {
    private static let snapshotsKey = "checknet.snapshots"
    private static let monitoredKey = "checknet.monitoredHosts"
    private static let historyFile = "history.json"
    private static let maxHistory = 2000

    // MARK: Snapshots (latest result per host, for widgets)

    static func saveSnapshot(_ snapshot: PingSnapshot) {
        var all = snapshots()
        all.removeAll { $0.host == snapshot.host }
        all.insert(snapshot, at: 0)
        if all.count > 12 { all = Array(all.prefix(12)) }
        if let data = try? JSONEncoder().encode(all) {
            AppGroup.defaults.set(data, forKey: snapshotsKey)
        }
    }

    static func snapshots() -> [PingSnapshot] {
        guard let data = AppGroup.defaults.data(forKey: snapshotsKey),
              let decoded = try? JSONDecoder().decode([PingSnapshot].self, from: data) else { return [] }
        return decoded
    }

    static func latestSnapshot(for host: String? = nil) -> PingSnapshot? {
        let all = snapshots()
        if let host { return all.first { $0.host == host } }
        return all.first
    }

    // MARK: Monitored hosts

    static func monitoredHosts() -> [String] {
        AppGroup.defaults.stringArray(forKey: monitoredKey) ?? []
    }

    static func setMonitoredHosts(_ hosts: [String]) {
        AppGroup.defaults.set(hosts, forKey: monitoredKey)
    }

    // MARK: History (file-backed)

    static func appendHistory(_ record: CheckRecord) {
        var records = history()
        records.insert(record, at: 0)
        if records.count > maxHistory { records = Array(records.prefix(maxHistory)) }
        writeHistory(records)
    }

    static func history() -> [CheckRecord] {
        let url = AppGroup.containerURL(for: historyFile)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([CheckRecord].self, from: data) else { return [] }
        return decoded
    }

    /// History filtered to one source (manual vs scheduled).
    static func history(source: HistorySource) -> [CheckRecord] {
        history().filter { $0.kind == source }
    }

    /// Removes a single record by id.
    static func deleteHistory(id: UUID) {
        writeHistory(history().filter { $0.id != id })
    }

    /// Clears every record, or only those from one source.
    static func clearHistory(source: HistorySource? = nil) {
        guard let source else { writeHistory([]); return }
        writeHistory(history().filter { $0.kind != source })
    }

    private static func writeHistory(_ records: [CheckRecord]) {
        let url = AppGroup.containerURL(for: historyFile)
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
