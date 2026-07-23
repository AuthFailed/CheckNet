import Foundation

/// Single source of truth for where the user's saved hosts live in
/// `UserDefaults`.
///
/// Both the SwiftUI `SavedHostsStore` and the App Intents `SavedHostQuery` read
/// this key. Keeping the key and codec in one place stops the two paths from
/// drifting — before this, a query that guessed the wrong key would silently
/// offer Siri an empty list of favorites.
enum SavedHostsPersistence {
    static let key = "checknet.savedHosts"

    /// Returns nil (not `[]`) when nothing was ever written, so the caller can
    /// tell "first launch" from "user deleted every host" and seed accordingly.
    static func load(from defaults: UserDefaults = .standard) -> [SavedHost]? {
        defaults.json([SavedHost].self, forKey: key)
    }

    static func save(_ hosts: [SavedHost], to defaults: UserDefaults = .standard) {
        defaults.setJSON(hosts, forKey: key)
    }
}

/// Pure matching used by the host `AppEntity` query, factored out of the App
/// Intents layer so it is unit-testable without an App Intents runtime.
enum SavedHostMatching {
    /// Deduplicated by address, global favorites before tool-scoped ones — the
    /// order Siri/Shortcuts should present them in.
    static func favorites(_ hosts: [SavedHost]) -> [SavedHost] {
        var seen = Set<String>()
        var out: [SavedHost] = []
        let ordered = hosts.sorted { ($0.toolID == nil ? 0 : 1) < ($1.toolID == nil ? 0 : 1) }
        for host in ordered {
            let value = host.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value.lowercased()).inserted else { continue }
            out.append(host)
        }
        return out
    }

    /// Saved hosts whose name or address contains `query`
    /// (case- and diacritic-insensitive). An empty query returns all favorites.
    static func filter(_ hosts: [SavedHost], query: String) -> [SavedHost] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = favorites(hosts)
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.value.localizedCaseInsensitiveContains(q)
        }
    }

    /// Whether a free-typed string is worth offering as an ad-hoc host entity,
    /// so a user can Siri/Shortcut *any* address, not only saved ones. Rejects
    /// obvious junk (spaces, bare words, over-long) to keep suggestions clean.
    static func isPlausibleHost(_ string: String) -> Bool {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= 253, !s.contains(" ") else { return false }
        if IPAddress.isValid(s) { return true }
        // A hostname needs an interior dot (label.label) and only host-legal chars.
        guard let dot = s.firstIndex(of: "."),
              dot != s.startIndex, dot != s.index(before: s.endIndex) else { return false }
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"
        )
        return s.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
