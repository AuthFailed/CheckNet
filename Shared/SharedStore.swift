import Foundation

/// Reads and writes shared state (last snapshots, monitored hosts, history)
/// used across the app, App Intents and Live Activities.
///
/// Everything here is reachable from more than one process at once: the app,
/// an App Intent running out-of-process, the scheduler and the monitoring loop.
/// Each mutation is a read-modify-write, so without coordination two writers
/// both read the same list, both append their own record and the second one to
/// finish silently discards the first one's work. Mutations therefore run
/// inside an advisory file lock — see `withLock`.
enum SharedStore {
    private static let snapshotsKey = "checknet.snapshots"
    private static let monitoredKey = "checknet.monitoredHosts"
    private static let historyFile = "history.json"
    private static let historyLockFile = "history.lock"
    private static let snapshotsLockFile = "snapshots.lock"
    private static let maxHistory = 2000

    // MARK: Cross-process locking

    /// Runs `body` while holding an advisory lock on `lockFile`.
    ///
    /// The lock deliberately lives in a file of its own. History is saved with
    /// an atomic write, which replaces the file by renaming a new one over it —
    /// a lock held on the data file would be attached to an inode that is about
    /// to be unlinked, and would protect nothing. `flock` is associated with the
    /// open file description, so separate `open` calls contend correctly whether
    /// they come from two threads or two processes.
    ///
    /// `body` must not call back into a locking API on the same file: `flock`
    /// would then block the thread against itself. That is why the mutating
    /// entry points below are written against the unlocked primitives.
    ///
    /// If the lock cannot be opened the work still runs. An unsynchronised write
    /// risks losing a record; refusing to write loses it for certain.
    private static func withLock<T>(_ lockFile: String, exclusive: Bool = true, _ body: () -> T) -> T {
        let path = AppGroup.containerURL(for: lockFile).path
        let fd = open(path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return body() }
        defer { close(fd) }
        guard flock(fd, exclusive ? LOCK_EX : LOCK_SH) == 0 else { return body() }
        defer { flock(fd, LOCK_UN) }
        return body()
    }

    // MARK: Snapshots (latest result per host, for widgets)

    static func saveSnapshot(_ snapshot: PingSnapshot) {
        withLock(snapshotsLockFile) {
            var all = snapshotsUnlocked()
            all.removeAll { $0.host == snapshot.host }
            all.insert(snapshot, at: 0)
            if all.count > 12 { all = Array(all.prefix(12)) }
            if let data = try? JSONEncoder().encode(all) {
                AppGroup.defaults.set(data, forKey: snapshotsKey)
            }
        }
    }

    /// Note the lock closes the lost-update window on the read-modify-write, but
    /// `UserDefaults` still caches per process, so a reader in another process
    /// can briefly observe an older list. That is tolerable here: snapshots are
    /// a display convenience and every entry is rewritten by the next check.
    static func snapshots() -> [PingSnapshot] {
        withLock(snapshotsLockFile, exclusive: false) { snapshotsUnlocked() }
    }

    private static func snapshotsUnlocked() -> [PingSnapshot] {
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
        withLock(historyLockFile) {
            var records = historyUnlocked()
            records.insert(record, at: 0)
            if records.count > maxHistory { records = Array(records.prefix(maxHistory)) }
            writeHistoryUnlocked(records)
        }
    }

    static func history() -> [CheckRecord] {
        withLock(historyLockFile, exclusive: false) { historyUnlocked() }
    }

    /// History filtered to one source (manual vs scheduled).
    static func history(source: HistorySource) -> [CheckRecord] {
        history().filter { $0.kind == source }
    }

    /// Removes a single record by id.
    static func deleteHistory(id: UUID) {
        withLock(historyLockFile) {
            writeHistoryUnlocked(historyUnlocked().filter { $0.id != id })
        }
    }

    /// Clears every record, or only those from one source.
    static func clearHistory(source: HistorySource? = nil) {
        withLock(historyLockFile) {
            guard let source else { writeHistoryUnlocked([]); return }
            writeHistoryUnlocked(historyUnlocked().filter { $0.kind != source })
        }
    }

    private static func historyUnlocked() -> [CheckRecord] {
        let url = AppGroup.containerURL(for: historyFile)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([CheckRecord].self, from: data) else { return [] }
        return decoded
    }

    private static func writeHistoryUnlocked(_ records: [CheckRecord]) {
        let url = AppGroup.containerURL(for: historyFile)
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
