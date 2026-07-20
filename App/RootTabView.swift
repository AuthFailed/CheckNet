import SwiftUI

/// The app's root: a Liquid Glass bottom tab bar (iOS 26) with Tests, Blocking
/// and Settings. The tab bar and its material come from the native `TabView`.
struct RootTabView: View {
    @Environment(AppSettings.self) private var settings
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
            Tab("Настройки", systemImage: "gearshape", value: 2) {
                SettingsView()
            }
        }
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
