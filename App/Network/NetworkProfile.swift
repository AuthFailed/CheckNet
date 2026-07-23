import Foundation
import Observation

/// A set of checks the user wants to run whenever they're on a particular
/// Wi-Fi network.
///
/// iOS won't wake the app on a network change, so profiles are driven two ways:
/// tapping "run now" inside the app (which reads the current SSID and matches),
/// and — the automation path — a personal Shortcuts automation "when I join
/// network X → run the CheckNet intent". This model is the in-app half.
struct NetworkProfile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// The Wi-Fi network name this profile applies to.
    var ssid: String
    /// Raw values of the blocking checks to run.
    var checkIDs: [String]
    /// Optional target override applied to checks that take one.
    var target: String = ""
    var isEnabled: Bool = true
}

/// Persists the user's network profiles.
@MainActor
@Observable
final class NetworkProfileStore {
    private(set) var profiles: [NetworkProfile]
    private let key = "checknet.networkProfiles"
    private let defaults = UserDefaults.standard

    init() {
        profiles = defaults.json([NetworkProfile].self, forKey: key) ?? []
    }

    /// The profile matching an SSID, if one is enabled for it. Matching is
    /// case-insensitive because SSIDs are compared as presented, not normalised.
    func profile(forSSID ssid: String) -> NetworkProfile? {
        profiles.first { $0.isEnabled && $0.ssid.caseInsensitiveCompare(ssid) == .orderedSame }
    }

    func add(_ profile: NetworkProfile) {
        profiles.append(profile)
        persist()
    }

    func update(_ profile: NetworkProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        persist()
    }

    func remove(_ profile: NetworkProfile) {
        profiles.removeAll { $0.id == profile.id }
        persist()
    }

    private func persist() {
        defaults.setJSON(profiles, forKey: key)
    }
}
