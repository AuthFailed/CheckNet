import Foundation

/// Shared identifiers and storage for data passed between the app, widgets,
/// and Live Activities. Falls back to standard defaults when the app-group
/// container is unavailable (e.g. unsigned simulator builds).
enum AppGroup {
    static let identifier = "group.com.checknet.app"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// A file URL inside the shared container for larger payloads (history).
    static func containerURL(for filename: String) -> URL {
        let fm = FileManager.default
        if let container = fm.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return container.appendingPathComponent(filename)
        }
        // Fallback: app's own documents directory.
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(filename)
    }
}
