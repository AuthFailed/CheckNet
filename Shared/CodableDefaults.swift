import Foundation

/// JSON persistence for `UserDefaults`, collapsing the `try? JSONEncoder()` /
/// `try? JSONDecoder()` dance that was copy-pasted across every store.
///
/// A free function pair rather than a `@propertyWrapper`: the stores are
/// `@Observable`, and a wrapper on their stored properties would not compose
/// with Observation's change tracking.
extension UserDefaults {
    /// Decodes a Codable value previously written with `setJSON(_:forKey:)`.
    /// Returns nil when the key is absent or the data no longer decodes.
    func json<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Stores a Codable value as JSON. A value that fails to encode is left
    /// unwritten rather than clearing the key.
    func setJSON<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        set(data, forKey: key)
    }
}
