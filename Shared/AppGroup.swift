import Foundation

/// Shared identifiers and storage for data passed between the app, widgets,
/// and Live Activities. Falls back to standard defaults when the app-group
/// container is unavailable (e.g. unsigned simulator builds).
enum AppGroup {
    static let identifier = "group.com.chrsnv.checknet"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// A file URL inside the shared container for larger payloads (history).
    ///
    /// The group container is used only when it actually exists on disk. Without
    /// the app-group entitlement — an unsandboxed process, a test bundle, the Mac
    /// build — `containerURL(forSecurityApplicationGroupIdentifier:)` still hands
    /// back a path, but nothing has created the directory, so every write to it
    /// fails. Combined with the `try?` on the write that looked exactly like a
    /// working app that silently kept no history.
    static func containerURL(for filename: String) -> URL {
        let fm = FileManager.default
        if let container = fm.containerURL(forSecurityApplicationGroupIdentifier: identifier),
           fm.fileExists(atPath: container.path) {
            return container.appendingPathComponent(filename)
        }
        // Fallback: app's own documents directory.
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(filename)
    }
}
