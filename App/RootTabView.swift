import SwiftUI

/// The app's root: a Liquid Glass bottom tab bar (iOS 26) with Tests, Blocking
/// and Settings. The tab bar and its material come from the native `TabView`.
struct RootTabView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SavedHostsStore.self) private var savedHosts
    @Environment(AppFlow.self) private var flow
    @Environment(ToolNavigator.self) private var navigator
    @State private var selection: Int = {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count { return Int(args[i + 1]) ?? 0 }
        return 0
    }()
    @State private var pendingImport: ImportPayload?

    /// Maps a control deep-link tab name onto the `TabView` selection.
    static func tabIndex(for name: String) -> Int? {
        switch name {
        case "tests": return 0
        case "blocking": return 1
        case "settings": return 2
        default: return nil
        }
    }

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
            // A control tap: jump to a tool or a tab.
            if let target = ControlDeepLink.target(from: url) {
                switch target {
                case let .tool(raw, host, run):
                    if let tool = Tool(rawValue: raw) {
                        selection = 0                       // controls live under Тесты
                        navigator.open(tool, autostart: run, host: host)
                    }
                case let .tab(name):
                    selection = Self.tabIndex(for: name) ?? selection
                }
                return
            }
            // Otherwise a scanned/shared host list.
            guard let hosts = HostSharing.hosts(from: url), !hosts.isEmpty else { return }
            pendingImport = ImportPayload(hosts: hosts)
        }
        .sheet(item: $pendingImport) { payload in
            ImportHostsSheet(hosts: payload.hosts)
        }
        // Onboarding and What's New live in a modifier because fullScreenCover
        // is iOS-only; on the Mac there is a separate root anyway (MacRootView).
        .modifier(FirstRunPresentations(flow: flow))
    }
}

/// First-launch onboarding and post-update What's New. iOS-only: the Mac has
/// its own root, and `fullScreenCover` does not exist there.
private struct FirstRunPresentations: ViewModifier {
    let flow: AppFlow

    #if os(iOS)
    func body(content: Content) -> some View {
        content
            // First launch takes the whole screen — nothing behind it is worth
            // seeing yet.
            .fullScreenCover(isPresented: Binding(
                get: { !flow.onboardingDone },
                set: { if !$0 { flow.completeOnboarding() } }
            )) {
                OnboardingView { flow.completeOnboarding() }
            }
            // After an update only — never on a first run, which
            // completeOnboarding() guards by stamping the current version.
            .sheet(isPresented: Binding(
                get: { flow.shouldShowWhatsNew || ProcessInfo.processInfo.arguments.contains("-showWhatsNew") },
                set: { if !$0 { flow.markWhatsNewSeen() } }
            )) {
                WhatsNewView { flow.markWhatsNewSeen() }
            }
    }
    #else
    func body(content: Content) -> some View { content }
    #endif
}
