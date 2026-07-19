import SwiftUI
import Observation

/// A saved host/target the user can quickly reuse, optionally scoped to a tool.
struct SavedHost: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var value: String       // host or IP
    var toolID: String?     // nil = global favorite
}

/// Persists the user's saved hosts across launches.
@Observable
final class SavedHostsStore {
    private(set) var hosts: [SavedHost]
    private let key = "checknet.savedHosts"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([SavedHost].self, from: data) {
            hosts = decoded
        } else {
            hosts = SavedHostsStore.seed
        }
    }

    func hosts(for tool: Tool) -> [SavedHost] {
        hosts.filter { $0.toolID == nil || $0.toolID == tool.id }
    }

    func add(name: String, value: String, tool: Tool?) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !hosts.contains(where: { $0.value == trimmed && $0.toolID == tool?.id }) else { return }
        hosts.append(SavedHost(name: name.isEmpty ? trimmed : name, value: trimmed, toolID: tool?.id))
        persist()
    }

    func remove(_ host: SavedHost) {
        hosts.removeAll { $0.id == host.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(hosts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static let seed: [SavedHost] = [
        SavedHost(name: "Дом-роутер", value: "192.168.1.1", toolID: nil),
        SavedHost(name: "Google DNS", value: "8.8.8.8", toolID: nil),
        SavedHost(name: "Cloudflare", value: "1.1.1.1", toolID: nil)
    ]
}
