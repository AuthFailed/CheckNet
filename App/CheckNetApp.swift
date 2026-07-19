import SwiftUI

@main
struct CheckNetApp: App {
    @State private var toolStore = ToolStore()
    @State private var savedHosts = SavedHostsStore()
    @State private var settings = AppSettings()

    init() {
        // Surface the iOS Local Network prompt up front so tests aren't silently
        // blocked on first launch (no-op on macOS / simulator).
        LocalNetworkPermission.shared.request()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(toolStore)
                .environment(savedHosts)
                .environment(settings)
        }
        #if os(macOS)
        .defaultSize(width: 460, height: 900)
        #endif
    }
}
