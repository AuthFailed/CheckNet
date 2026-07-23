import SwiftUI
import CoreSpotlight

@main
struct CheckNetApp: App {
    @State private var toolStore = ToolStore()
    @State private var savedHosts: SavedHostsStore
    @State private var cloudSync: CloudHostSync
    @State private var settings = AppSettings()
    @State private var webhooks = WebhookSettings()
    @State private var networkProfiles = NetworkProfileStore()
    @State private var scheduledTasks: ScheduledTaskStore
    @State private var scheduler: TaskScheduler
    @State private var flow = AppFlow()
    @State private var navigator = ToolNavigator()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = ScheduledTaskStore()
        _scheduledTasks = State(initialValue: store)
        _scheduler = State(initialValue: TaskScheduler(store: store))

        // One saved-hosts store, shared with the iCloud sync that mirrors it.
        let hosts = SavedHostsStore()
        _savedHosts = State(initialValue: hosts)
        _cloudSync = State(initialValue: CloudHostSync(store: hosts))

        // Must be registered before the app finishes launching.
        #if os(iOS)
        BackgroundMonitor.register()
        #endif

        // The Local Network prompt is deliberately *not* requested here any
        // more. Asking on launch, before any context, is the anti-pattern that
        // gets it denied for good; it now happens the first time a tool that
        // needs it is opened, behind a screen that explains why (PrePermissionSheet).
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
            .environment(flow)
            .environment(navigator)
    }

    /// Index the catalogue into Spotlight and route a tapped result to its tool,
    /// and resume a tool handed off from another device.
    private func spotlight<Content: View>(_ content: Content) -> some View {
        content
            .task { SpotlightIndexer.index() }
            .task { cloudSync.start() }
            .task { configureNotifications() }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                if let tool = SpotlightIndexer.tool(from: activity) { navigator.open(tool) }
            }
            .onContinueUserActivity(ToolActivity.type) { activity in
                if let payload = ToolActivity.payload(from: activity.userInfo),
                   let tool = Tool(rawValue: payload.toolRawValue) {
                    navigator.open(tool, host: payload.host)
                }
            }
    }

    var body: some Scene {
        #if os(macOS)
        macScenes
        #else
        phoneScene
        #endif
    }

    private var mainWindowContent: some View {
        #if os(macOS)
        // The Mac has its own root: one sidebar, one detail column, rather than
        // an adaptive tab bar with a split view nested inside each tab.
        spotlight(withEnvironment(MacRootView())
            .onAppear { WebhookReporter.settings = webhooks })
        #else
        spotlight(withEnvironment(RootTabView())
            .onAppear { WebhookReporter.settings = webhooks })
        #endif
    }

    /// Scheduling is foreground-only; pause it when the app isn't active so it
    /// doesn't waste a suspended tick, resume when it returns.
    private func handle(_ phase: ScenePhase) {
        switch phase {
        case .active:
            scheduler.start()
        case .background:
            scheduler.stop()
            #if os(iOS)
            BackgroundMonitor.schedule()
            #endif
        default:
            scheduler.stop()
        }
    }

    /// Wires the notification delegate and routes its actions. A tapped alert
    /// opens the host in Ping; "Проверить снова" re-runs the check pass.
    private func configureNotifications() {
        HostNotifier.shared.configure()
        HostNotifier.shared.onAction = { actionID, host in
            switch actionID {
            case MonitorNotification.actionOpen:
                navigator.open(host.isEmpty ? .monitoring : .ping, host: host.isEmpty ? nil : host)
            case MonitorNotification.actionRecheck:
                #if os(iOS)
                Task { await BackgroundMonitor.runPass() }
                #endif
            default:
                break
            }
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
