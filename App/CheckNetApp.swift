import SwiftUI

@main
struct CheckNetApp: App {
    @State private var toolStore = ToolStore()
    @State private var savedHosts = SavedHostsStore()

    var body: some Scene {
        WindowGroup {
            CatalogView()
                .environment(toolStore)
                .environment(savedHosts)
        }
        #if os(macOS)
        .defaultSize(width: 420, height: 820)
        #endif
    }
}
