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
    #endif
    @State private var path: [ToolRoute] = []
    @State private var selection: ToolRoute?
    @State private var query: String = ""
    @State private var showHistory = false

    /// Two columns where there is room for them. A Mac window always qualifies;
    /// on iOS it is the regular width class, which covers iPad landscape and a
    /// large iPad in portrait but never an iPhone.
    private var isWide: Bool {
        #if os(iOS)
        sizeClass == .regular
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
                // Without an explicit width the column collapses on macOS —
                // where `.sidebarAdaptable` already spends one column on the
                // tab list — and tool names wrap one letter per line until the
                // user drags the divider open.
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 480)
                .modifier(CatalogChrome(query: $query, showHistory: $showHistory))
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

    private var catalogList: some View {
        List(selection: isWide ? $selection : .constant(nil)) {
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
    }

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
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .textCase(nil)
            .font(.footnote)
        }
    }

    private var searchResults: some View {
        let matches = Tool.allCases.filter {
            !$0.isCensorshipCheck &&
            ($0.title.localizedCaseInsensitiveContains(query) ||
             $0.subtitle.localizedCaseInsensitiveContains(query))
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
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(tool.isImplemented ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(LocalizedStringKey(tool.title))
                        .font(.body)
                        .foregroundStyle(.primary)
                    if isPinned {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
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
