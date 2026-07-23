import Foundation

/// Mirrors saved hosts through iCloud key-value storage so favorites follow the
/// user across their devices.
///
/// **Dormant by default.** iCloud KVS needs the `ubiquity-kvstore-identifier`
/// entitlement, which only a paid developer account can sign — the same reason
/// Access Wi-Fi Information is left out (see `App/CheckNet.entitlements` and
/// `CurrentNetwork.isSSIDReadable`). `isAvailable` is the code-side half of that
/// switch: flip it to `true` and add the entitlement in the *same* commit, never
/// one alone. While it is false the app says iCloud sync is unavailable rather
/// than offering a control that quietly does nothing.
@MainActor
final class CloudHostSync {
    /// Flip together with the `com.apple.developer.ubiquity-kvstore-identifier`
    /// entitlement. See the type comment.
    static let isAvailable = false

    private static let key = "checknet.savedHosts.cloud"

    private let store: SavedHostsStore
    private var observer: NSObjectProtocol?

    init(store: SavedHostsStore) { self.store = store }

    /// Begins observing iCloud and reconciles both directions once. A no-op
    /// while the build cannot sign the entitlement.
    func start() {
        guard Self.isAvailable else { return }
        let kv = NSUbiquitousKeyValueStore.default
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kv, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pull() }
        }
        kv.synchronize()
        pull()   // adopt anything already in the cloud…
        push()   // …then publish the merged result back.
    }

    /// Merge remote favorites into the local store (remote never deletes local).
    func pull() {
        guard Self.isAvailable else { return }
        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: Self.key),
              let remote = try? JSONDecoder().decode([SavedHost].self, from: data) else { return }
        store.replaceAll(with: SavedHostMerge.union(store.hosts, remote))
    }

    /// Publish local favorites to iCloud.
    func push() {
        guard Self.isAvailable else { return }
        guard let data = try? JSONEncoder().encode(store.hosts) else { return }
        NSUbiquitousKeyValueStore.default.set(data, forKey: Self.key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }
}
