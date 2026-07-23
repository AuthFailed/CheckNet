import AppIntents

/// A host/IP the user can pick in Siri and the Shortcuts editor.
///
/// Exposing saved hosts as an `AppEntity` (rather than a bare `String`
/// parameter) means the Shortcuts picker offers the user's own favorites by
/// name — "Дом-роутер", "Cloudflare" — and Siri can resolve a spoken favorite,
/// while still letting anyone type a raw address.
struct SavedHostEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Хост")
    static let defaultQuery = SavedHostQuery()

    /// The literal address, doubling as the stable identifier: a saved favorite
    /// and the same address typed by hand collapse to one entity.
    var id: String
    var name: String

    /// What the engines actually receive.
    var value: String { id }

    init(value: String, name: String? = nil) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = trimmed
        let candidate = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = candidate.isEmpty ? trimmed : candidate
    }

    init(_ host: SavedHost) { self.init(value: host.value, name: host.name) }

    var displayRepresentation: DisplayRepresentation {
        name == id
            ? DisplayRepresentation(title: "\(id)")
            : DisplayRepresentation(title: "\(name)", subtitle: "\(id)")
    }
}

/// Backs `SavedHostEntity` with the user's saved hosts, and — because it is an
/// `EntityStringQuery` — resolves free-typed addresses too, so an intent isn't
/// limited to the favorites list.
struct SavedHostQuery: EntityStringQuery {
    private var saved: [SavedHost] { SavedHostsPersistence.load() ?? [] }

    func entities(for identifiers: [String]) async throws -> [SavedHostEntity] {
        let hosts = saved
        return identifiers.map { id in
            if let match = hosts.first(where: { $0.value == id }) { return SavedHostEntity(match) }
            return SavedHostEntity(value: id)   // an address the user typed earlier
        }
    }

    func entities(matching string: String) async throws -> [SavedHostEntity] {
        var out = SavedHostMatching.filter(saved, query: string).map { SavedHostEntity($0) }
        let typed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        // Offer the raw address too, so any host is runnable — not just saved ones.
        if SavedHostMatching.isPlausibleHost(typed),
           !out.contains(where: { $0.id.caseInsensitiveCompare(typed) == .orderedSame }) {
            out.insert(SavedHostEntity(value: typed), at: 0)
        }
        return out
    }

    func suggestedEntities() async throws -> [SavedHostEntity] {
        SavedHostMatching.favorites(saved).map { SavedHostEntity($0) }
    }
}
