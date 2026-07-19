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

    /// Global favorites split into IP literals and domain names for the settings UI.
    var savedIPs: [SavedHost] { hosts.filter { $0.toolID == nil && SavedHostsStore.isIP($0.value) } }
    var savedDomains: [SavedHost] { hosts.filter { $0.toolID == nil && !SavedHostsStore.isIP($0.value) } }

    static func isIP(_ value: String) -> Bool {
        var v4 = in_addr(); var v6 = in6_addr()
        return value.withCString { inet_pton(AF_INET, $0, &v4) == 1 || inet_pton(AF_INET6, $0, &v6) == 1 }
    }

    func update(_ host: SavedHost, name: String, value: String) {
        guard let idx = hosts.firstIndex(where: { $0.id == host.id }) else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hosts[idx].name = name.isEmpty ? trimmed : name
        hosts[idx].value = trimmed
        persist()
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
