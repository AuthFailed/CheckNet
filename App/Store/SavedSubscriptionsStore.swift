import SwiftUI
import Observation

/// Persists subscriptions the user saved for quick reuse in the VPN tools.
/// Mirrors `SavedHostsStore`, but in its own list so subscription links never
/// show up in the host bookmark menus.
@Observable
final class SavedSubscriptionsStore {
    private(set) var items: [SavedSubscription]

    init() {
        items = SavedSubscriptionsPersistence.load() ?? []
    }

    /// Adds unless the same value is already saved. Returns false on duplicate.
    @discardableResult
    func add(name: String, value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !contains(trimmed) else { return false }
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        items.append(SavedSubscription(name: label.isEmpty ? Self.suggestedName(for: trimmed) : label,
                                       value: trimmed))
        persist()
        return true
    }

    func update(_ item: SavedSubscription, name: String, value: String) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items[idx].name = name.isEmpty ? Self.suggestedName(for: trimmed) : name
        items[idx].value = trimmed
        persist()
    }

    func remove(_ item: SavedSubscription) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func remove(atOffsets offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        persist()
    }

    func contains(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.contains { $0.value == trimmed }
    }

    /// A readable default name: the host for URLs, the scheme for crypto links.
    static func suggestedName(for value: String) -> String {
        if let host = URL(string: value)?.host { return host }
        let lower = value.lowercased()
        if lower.hasPrefix("happ://") { return "Happ-ссылка" }
        if lower.hasPrefix("incy://") { return "Incy-ссылка" }
        return String(value.prefix(24))
    }

    private func persist() { SavedSubscriptionsPersistence.save(items) }
}
