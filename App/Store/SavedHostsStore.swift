import SwiftUI
import Observation

/// Persists the user's saved hosts across launches.
@Observable
final class SavedHostsStore {
    private(set) var hosts: [SavedHost]

    init() {
        hosts = SavedHostsPersistence.load() ?? SavedHostsStore.seed
    }

    func hosts(for tool: Tool) -> [SavedHost] {
        hosts.filter { $0.toolID == nil || $0.toolID == tool.id }
    }

    /// Global favorites split into IP literals and domain names for the settings UI.
    var savedIPs: [SavedHost] { hosts.filter { $0.toolID == nil && SavedHostsStore.isIP($0.value) } }
    var savedDomains: [SavedHost] { hosts.filter { $0.toolID == nil && !SavedHostsStore.isIP($0.value) } }

    static func isIP(_ value: String) -> Bool { IPAddress.isValid(value) }

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

    /// Adds every incoming host that isn't already saved globally.
    /// Returns how many were added and how many were skipped as duplicates.
    @discardableResult
    func merge(_ incoming: [SavedHost]) -> (added: Int, skipped: Int) {
        var added = 0, skipped = 0
        for host in incoming {
            let value = host.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { skipped += 1; continue }
            guard !hosts.contains(where: { $0.value == value && $0.toolID == nil }) else { skipped += 1; continue }
            hosts.append(SavedHost(name: host.name.isEmpty ? value : host.name, value: value, toolID: nil))
            added += 1
        }
        if added > 0 { persist() }
        return (added, skipped)
    }

    /// True when the host is already saved as a global favorite.
    func containsGlobally(_ value: String) -> Bool {
        hosts.contains { $0.value == value && $0.toolID == nil }
    }

    func remove(_ host: SavedHost) {
        hosts.removeAll { $0.id == host.id }
        persist()
    }

    private func persist() {
        SavedHostsPersistence.save(hosts)
    }

    static let seed: [SavedHost] = [
        SavedHost(name: "Дом-роутер", value: "192.168.1.1", toolID: nil),
        SavedHost(name: "Google DNS", value: "8.8.8.8", toolID: nil),
        SavedHost(name: "Cloudflare", value: "1.1.1.1", toolID: nil)
    ]
}
