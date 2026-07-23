import Foundation

/// A monitored host and its latest observed state. Shared so the foreground
/// monitor and the background refresh read and write one persisted list.
struct MonitoredEntry: Identifiable, Codable, Hashable, Sendable {
    var id: String { host }
    var host: String
    var status: PingSnapshot.Status = .unknown
    var lastLatency: Double?
    var lastChecked: Date?
    var lossPercent: Double = 0
}

/// Single source of truth for the monitored-host list in the app group, so the
/// in-app `MonitoringManager` and the out-of-process `BackgroundMonitor` never
/// disagree about which hosts to watch or their last-seen status.
enum MonitorStore {
    static let key = "checknet.monitorEntries"

    static func load(from defaults: UserDefaults = AppGroup.defaults) -> [MonitoredEntry] {
        defaults.json([MonitoredEntry].self, forKey: key) ?? []
    }

    static func save(_ entries: [MonitoredEntry], to defaults: UserDefaults = AppGroup.defaults) {
        defaults.setJSON(entries, forKey: key)
    }
}
