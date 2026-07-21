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

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(toolStore)
                .environment(savedHosts)
                .environment(settings)
                .environment(webhooks)
                .environment(networkProfiles)
                .environment(scheduledTasks)
                .environment(scheduler)
                .onAppear { WebhookReporter.settings = webhooks }
        }
        #if os(macOS)
        .defaultSize(width: 460, height: 900)
        #endif
        .onChange(of: scenePhase) { _, phase in
            // Scheduling is foreground-only; pause it when the app isn't active
            // so it doesn't waste a suspended tick, resume when it returns.
            switch phase {
            case .active: scheduler.start()
            default: scheduler.stop()
            }
        }
    }
}
