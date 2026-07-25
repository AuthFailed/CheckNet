import Foundation

/// A subscription the user saved for reuse in the VPN tools — a plain URL, a
/// `happ://crypt…` / `incy://crypt1/…` link, or pasted content.
///
/// Kept separate from `SavedHost`: a subscription is not a ping target, and
/// mixing them would pollute the host bookmark menus of every other tool.
struct SavedSubscription: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var value: String

    /// Short label for the kind of link, for the list UI.
    var kind: String {
        let v = value.lowercased()
        if v.hasPrefix("happ://") { return "Happ" }
        if v.hasPrefix("incy://") { return "Incy" }
        if v.hasPrefix("http") { return "URL" }
        return "текст"
    }
}

/// Single source of truth for where saved subscriptions live in `UserDefaults`.
enum SavedSubscriptionsPersistence {
    static let key = "checknet.savedSubscriptions"

    static func load(from defaults: UserDefaults = .standard) -> [SavedSubscription]? {
        defaults.json([SavedSubscription].self, forKey: key)
    }

    static func save(_ items: [SavedSubscription], to defaults: UserDefaults = .standard) {
        defaults.setJSON(items, forKey: key)
    }
}
