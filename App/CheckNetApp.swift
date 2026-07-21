import SwiftUI

@main
struct CheckNetApp: App {
    @State private var toolStore = ToolStore()
    @State private var savedHosts = SavedHostsStore()
    @State private var settings = AppSettings()
    @State private var webhooks = WebhookSettings()
    @State private var networkProfiles = NetworkProfileStore()
    @State private var scheduledTasks: ScheduledTaskStore
    @State private var scheduler: TaskScheduler
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = ScheduledTaskStore()
        _scheduledTasks = State(initialValue: store)
        _scheduler = State(initialValue: TaskScheduler(store: store))

        // Surface the iOS Local Network prompt up front so tests aren't silently
        // blocked on first launch (no-op on macOS / simulator).
        LocalNetworkPermission.shared.request()
    }

    /// Every scene needs the same object graph; keeping it in one place stops the
    /// window and the Settings scene from drifting apart.
    private func withEnvironment<Content: View>(_ content: Content) -> some View {
        content
            .environment(toolStore)
            .environment(savedHosts)
            .environment(settings)
            .environment(webhooks)
            .environment(networkProfiles)
            .environment(scheduledTasks)
            .environment(scheduler)
    }

    var body: some Scene {
        #if os(macOS)
        macScenes
        #else
        phoneScene
        #endif
    }

    private var mainWindowContent: some View {
        withEnvironment(RootTabView())
            .onAppear { WebhookReporter.settings = webhooks }
    }

    /// Scheduling is foreground-only; pause it when the app isn't active so it
    /// doesn't waste a suspended tick, resume when it returns.
    private func handle(_ phase: ScenePhase) {
        switch phase {
        case .active: scheduler.start()
        default: scheduler.stop()
        }
    }

    #if os(macOS)
    @SceneBuilder
    private var macScenes: some Scene {
        WindowGroup(id: MacWindow.main) {
            mainWindowContent
        }
        // 460×900 made the Mac app a phone-shaped strip; a diagnostics tool with
        // a sidebar wants a normal window.
        //
        // Deliberately no `.windowResizability(.contentMinSize)`, which the issue
        // suggested: with it the window never appears at all — the sidebar layout
        // reports no satisfiable minimum, so AppKit has nothing to size to and
        // the app launches with a menu bar and zero windows. Default
        // resizability lets the user size it freely, which is what we want here.
        .defaultSize(width: 1100, height: 760)
        .commands { CheckNetCommands() }
        .onChange(of: scenePhase) { _, phase in handle(phase) }

        // ⌘, like every Mac app, rather than a Settings tab copied from iPhone.
        Settings {
            withEnvironment(SettingsView())
                .frame(minWidth: 520, minHeight: 460)
        }

        MenuBarExtra {
            MenuBarStatus()
        } label: {
            MenuBarIcon()
        }
    }
    #else
    private var phoneScene: some Scene {
        WindowGroup {
            mainWindowContent
        }
        .onChange(of: scenePhase) { _, phase in handle(phase) }
    }
    #endif
}

/// Window identifier, so the menu bar item can bring the main window back after
/// it has been closed.
enum MacWindow {
    static let main = "checknet.main"
}
