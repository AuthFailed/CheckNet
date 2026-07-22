import SwiftUI

/// The app's root: a Liquid Glass bottom tab bar (iOS 26) with Tests, Blocking
/// and Settings. The tab bar and its material come from the native `TabView`.
struct RootTabView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SavedHostsStore.self) private var savedHosts
    @State private var selection: Int = {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count { return Int(args[i + 1]) ?? 0 }
        return 0
    }()
    @State private var pendingImport: ImportPayload?

    var body: some View {
        TabView(selection: $selection) {
            Tab("Тесты", systemImage: "wrench.and.screwdriver", value: 0) {
                CatalogView()
            }
            Tab("Блокировки", systemImage: "hand.raised", value: 1) {
                BlockingView()
            }
            // Not on macOS: settings live in the ⌘, scene there, and a
            // Settings tab as well would be two doors to the same room.
            #if !os(macOS)
            Tab("Настройки", systemImage: "gearshape", value: 2) {
                SettingsView()
            }
            #endif
        }
        // On iPhone this stays the Liquid Glass tab bar. Where there is room —
        // iPad regular width, a Mac window — the system turns the same three
        // tabs into a sidebar, which is what those platforms expect instead of
        // a tab bar pinned to the bottom of a 13" screen.
        .tabViewStyle(.sidebarAdaptable)
        // Saving a host is confirmed by a row appearing in a menu the user is
        // not looking at, so it gets a tap of its own. One place rather than
        // each of the twenty screens that can save.
        .haptic(.light, trigger: savedHosts.hosts.count)
        .preferredColorScheme(settings.theme.colorScheme)
        .environment(\.locale, settings.language.localeIdentifier.map(Locale.init) ?? .current)
        .onOpenURL { url in
            guard let hosts = HostSharing.hosts(from: url), !hosts.isEmpty else { return }
            pendingImport = ImportPayload(hosts: hosts)
        }
        .sheet(item: $pendingImport) { payload in
            ImportHostsSheet(hosts: payload.hosts)
        }
    }
}
