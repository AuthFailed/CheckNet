import SwiftUI

/// Routing value: which tool to open and whether to auto-run it.
struct ToolRoute: Hashable {
    let tool: Tool
    var autostart: Bool = false
    var openSettings: Bool = false
    var presetHost: String? = nil
}

/// Debug/deep-link launch options parsed from process arguments.
/// e.g. `CheckNet -openTool ping -host 1.1.1.1 -run 1`
enum LaunchOptions {
    static var initialRoute: ToolRoute? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-openTool"), idx + 1 < args.count,
              let tool = Tool(rawValue: args[idx + 1]) else { return nil }
        var host: String? = nil
        if let h = args.firstIndex(of: "-host"), h + 1 < args.count { host = args[h + 1] }
        let run = args.contains("-run")
        return ToolRoute(tool: tool, autostart: run, presetHost: host)
    }
}

struct CatalogView: View {
    @Environment(ToolStore.self) private var store
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(AppFlow.self) private var flow
    #endif
    @State private var path: [ToolRoute] = []
    @State private var selection: ToolRoute?
    @State private var query: String = ""
    @State private var showHistory = false

    /// Two columns where there is genuinely room. A Mac window always qualifies.
    /// On iOS "regular width" alone is not enough: a Pro Max in landscape reports
    /// regular width with no vertical room, and a sidebar there costs width the
    /// tool needs.
    private var isWide: Bool {
        #if os(iOS)
        // Same reasoning as ToolScaffold: a Pro Max in landscape is regular
        // width but has no vertical room, and a sidebar there costs width the
        // tool needs. Compact height means one column.
        sizeClass == .regular && verticalSizeClass != .compact
        #else
        true
        #endif
    }

    var body: some View {
        Group {
            if isWide {
                splitLayout
            } else {
                stackLayout
            }
        }
        // Pinning shows up as a star sliding into a row that may be off screen.
        .haptic(.light, trigger: store.pinnedTools.count)
        .onAppear {
            if let route = LaunchOptions.initialRoute {
                // The deep link has to land in whichever column model is live,
                // otherwise `-openTool` silently does nothing on iPad.
                if isWide {
                    if selection == nil { selection = route }
                } else if path.isEmpty {
                    path.append(route)
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-openHistory") {
                showHistory = true
            }
        }
    }

    /// Opens a route in whichever column model this layout uses.
    private func open(_ route: ToolRoute) {
        if isWide {
            selection = route
        } else {
            path.append(route)
        }
    }

    // MARK: Layouts

    /// iPhone and compact widths: one column, tools push onto the stack.
    private var stackLayout: some View {
        NavigationStack(path: $path) {
            catalogList
                .navigationDestination(for: ToolRoute.self) { route in
                    ToolDestinationView(route: route)
                }
                .modifier(CatalogChrome(query: $query, showHistory: $showHistory))
        }
    }

    /// iPad and Mac: the catalog stays in a sidebar and the tool fills the
    /// detail column, instead of a list row stretching across the window.
    private var splitLayout: some View {
        NavigationSplitView {
            catalogList
                .modifier(CatalogChrome(query: $query, showHistory: $showHistory))
                // `.sidebarAdaptable` already spends one column on the tab list,
                // so this one starts near zero and tool names wrap a letter per
                // line until the divider is dragged open.
                //
                // Both halves are needed. The column width states the intent,
                // but AppKit restores a saved divider position per window, so a
                // stale narrow value from an earlier run wins over `ideal`. The
                // frame is the floor that a restored position cannot go under.
                .frame(minWidth: 240)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 480)
        } detail: {
            NavigationStack {
                if let selection {
                    ToolDestinationView(route: selection)
                        // Without an identity the detail column reuses the
                        // previous tool's view state when the selection changes.
                        .id(selection)
                } else {
                    ContentUnavailableView(
                        "Выберите инструмент",
                        systemImage: "wrench.and.screwdriver",
                        description: Text("Слева — все проверки. Выберите любую, чтобы запустить её.")
                    )
                }
            }
        }
    }

    /// Two lists rather than one with a `.constant(nil)` selection: a list that
    /// carries *any* selection binding puts its rows into selection mode, where
    /// a tap marks the row instead of following its `NavigationLink`. That left
    /// the phone catalog highlighting a row and going nowhere.
    @ViewBuilder
    private var catalogList: some View {
        if isWide {
            List(selection: $selection) { catalogRows }
        } else {
            List { catalogRows }
        }
    }

    @ViewBuilder
    private var catalogRows: some View {
        #if os(iOS)
        if flow.localNetworkDenied && query.isEmpty {
            localNetworkDeniedBanner
        }
        #endif
        if !store.pinnedTools.isEmpty && query.isEmpty {
            pinnedSection
        }
        if query.isEmpty {
            ForEach(ToolCatalog.sections) { section in
                catalogSection(section)
            }
        } else {
            searchResults
        }
    }

    #if os(iOS)
    /// Shown after the local-network prompt came back denied: scanning, the
    /// device browser and Bonjour cannot work, and the way back is in Settings.
    /// Status is carried by an icon and words, not colour, and "Скрыть" leaves
    /// an equal way out.
    @ViewBuilder
    private var localNetworkDeniedBanner: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text("Доступ к локальной сети отклонён")
                        .font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Text("Без него сканер сети, обзор устройств и Bonjour не работают. Включить можно в Настройках iOS.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Открыть Настройки", destination: url)
                            .font(.subheadline.weight(.semibold))
                    }
                    Button("Скрыть") { flow.localNetworkDenied = false }
                        .font(.subheadline)
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 4)
        }
    }
    #endif

    // MARK: Pinned

    private var pinnedSection: some View {
        Section {
            ForEach(store.pinnedTools) { tool in
                toolRow(tool).id("pin-\(tool.id)")
            }
        } header: {
            Label {
                Text("Избранное")
            } icon: {
                Image(systemName: "star.fill").foregroundStyle(.orange)
            }
            .font(.footnote)
            .textCase(nil)
        }
    }

    // MARK: Category sections

    private func catalogSection(_ section: ToolSection) -> some View {
        let collapsed = store.isCollapsed(section)
        return Section {
            if !collapsed {
                ForEach(section.tools) { tool in
                    toolRow(tool).id("cat-\(tool.id)")
                }
            }
        } header: {
            Button {
                withAnimation(.snappy(duration: 0.25)) { store.toggleCollapse(section) }
            } label: {
                HStack {
                    Text(LocalizedStringKey(section.title))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .textCase(nil)
            .font(.footnote)
            // The chevron is hidden, so the button says its own state instead.
            .accessibilityLabel(Text(LocalizedStringKey(section.title)))
            .accessibilityValue(collapsed ? Text("свёрнуто") : Text("развёрнуто"))
            .accessibilityHint(collapsed ? Text("Развернуть раздел") : Text("Свернуть раздел"))
        }
    }

    private var searchResults: some View {
        let matches = Tool.allCases.filter {
            !$0.isCensorshipCheck && $0.matches(query)
        }
        return Section {
            if matches.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ForEach(matches) { tool in
                    toolRow(tool, showSubtitle: true)
                }
            }
        }
    }

    // MARK: Row

    @ViewBuilder
    private func toolRow(_ tool: Tool, showSubtitle: Bool = false) -> some View {
        let route = ToolRoute(tool: tool)
        Group {
            if isWide {
                // The sidebar drives the detail column through List selection,
                // so the row is a plain tagged row.
                ToolRowView(tool: tool, showSubtitle: showSubtitle, isPinned: store.isPinned(tool))
                    .tag(route)
            } else {
                // A real NavigationLink rather than onTapGesture: it gives the
                // row its disclosure affordance, keyboard and VoiceOver
                // behaviour, and press feedback for free.
                NavigationLink(value: route) {
                    ToolRowView(tool: tool, showSubtitle: showSubtitle, isPinned: store.isPinned(tool))
                }
            }
        }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    store.togglePin(tool)
                } label: {
                    Label(store.isPinned(tool) ? LocalizedStringKey("Открепить") : LocalizedStringKey("Закрепить"),
                          systemImage: store.isPinned(tool) ? "star.slash" : "star")
                }
                .tint(.orange)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if tool.isImplemented {
                    Button {
                        open(ToolRoute(tool: tool, autostart: true))
                    } label: {
                        Label("Запустить", systemImage: "play.fill")
                    }
                    .tint(.green)
                }
                Button {
                    open(ToolRoute(tool: tool, openSettings: true))
                } label: {
                    Label("Настройки", systemImage: "slider.horizontal.3")
                }
                .tint(.gray)
            }
    }
}

/// Renders a single catalog row.
struct ToolRowView: View {
    let tool: Tool
    var showSubtitle: Bool = false
    var isPinned: Bool = false

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: tool.systemImage)
                .font(.title3)
                .foregroundStyle(tool.isImplemented ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(LocalizedStringKey(tool.title))
                        .font(.body)
                        .foregroundStyle(.primary)
                    if isPinned {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("В избранном")
                    }
                }
                if showSubtitle {
                    Text(LocalizedStringKey(tool.subtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if !tool.isImplemented {
                Text("скоро")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            InfoButton(title: tool.title, systemImage: tool.systemImage,
                       message: tool.info, note: tool.sensitivityNote)
            // No hand-drawn chevron: in compact the NavigationLink supplies the
            // disclosure indicator (drawing our own gave every row two), and in
            // the sidebar the selection highlight is the affordance.
        }
        .padding(.vertical, 2)
    }
}

/// Routes a tool to its screen (implemented or a coming-soon scaffold).
struct ToolDestinationView: View {
    let route: ToolRoute

    var body: some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    InfoButton(title: route.tool.title, systemImage: route.tool.systemImage,
                               message: route.tool.info, note: route.tool.sensitivityNote)
                }
            }
            .modifier(LocalNetworkGate(tool: route.tool))
    }

    @ViewBuilder
    private var content: some View {
        switch route.tool {
        case .ping:
            PingView(autostart: route.autostart, openSettings: route.openSettings, presetHost: route.presetHost)
        case .traceroute:
            TracerouteView(presetHost: route.presetHost, autostart: route.autostart)
        case .mtr:
            MTRView(presetHost: route.presetHost, autostart: route.autostart)
        case .cgnatDetect:
            NATView(autostart: route.autostart)
        case .monitoring:
            MonitoringView()
        case .networkBrowser:
            NetworkBrowserView()
        case .speedTest:
            SpeedTestView()
        case .dns:
            DNSLookupView(presetHost: route.presetHost, autostart: route.autostart)
        case .dnsCompare:
            DNSCompareView(presetHost: route.presetHost, autostart: route.autostart)
        case .dnsTamper:
            DNSTamperView(presetHost: route.presetHost, autostart: route.autostart)
        case .whois:
            WhoisView(presetHost: route.presetHost, autostart: route.autostart)
        case .blacklist:
            BlacklistView(presetHost: route.presetHost, autostart: route.autostart)
        case .wakeOnLan:
            WakeOnLanView()
        case .mtuDiscovery:
            MTUView(presetHost: route.presetHost, autostart: route.autostart)
        case .ipScanner:
            IPScannerView(autostart: route.autostart)
        case .bonjour:
            BonjourView()
        case .portScan:
            PortScanView(presetHost: route.presetHost, autostart: route.autostart)
        case .tlsInspector:
            TLSInspectorView(presetHost: route.presetHost, autostart: route.autostart)
        case .hostToIP:
            HostToIPView(presetHost: route.presetHost, autostart: route.autostart)
        case .reverseDns:
            ReverseDNSView(presetHost: route.presetHost, autostart: route.autostart)
        case .interfaces:
            InterfacesView()
        default:
            PlaceholderToolView(tool: route.tool)
        }
    }
}

/// Title, search, history button and list style — identical in both layouts,
/// so they live in one place rather than being repeated per column model.
private struct CatalogChrome: ViewModifier {
    @Binding var query: String
    @Binding var showHistory: Bool

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .navigationTitle("Инструменты")
            #if os(iOS)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск")
            #else
            .searchable(text: $query, prompt: "Поиск")
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("История")
                }
            }
            .sheet(isPresented: $showHistory) {
                HistoryView()
                    .presentationDetents([.large])
            }
    }
}
