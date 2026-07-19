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
    @State private var path: [ToolRoute] = []
    @State private var query: String = ""

    var body: some View {
        NavigationStack(path: $path) {
            List {
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
            .listStyle(.insetGrouped)
            .navigationTitle("Инструменты")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск")
            .navigationDestination(for: ToolRoute.self) { route in
                ToolDestinationView(route: route)
            }
        }
        .onAppear {
            if path.isEmpty, let route = LaunchOptions.initialRoute {
                path.append(route)
            }
        }
    }

    // MARK: Pinned

    private var pinnedSection: some View {
        Section {
            ForEach(store.pinnedTools) { tool in
                toolRow(tool)
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
                    toolRow(tool)
                }
            }
        } header: {
            Button {
                withAnimation(.snappy(duration: 0.25)) { store.toggleCollapse(section) }
            } label: {
                HStack {
                    Text(section.title)
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
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.subtitle.localizedCaseInsensitiveContains(query)
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

    private func toolRow(_ tool: Tool, showSubtitle: Bool = false) -> some View {
        ToolRowView(tool: tool, showSubtitle: showSubtitle)
            .contentShape(.rect)
            .onTapGesture { path.append(ToolRoute(tool: tool)) }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    withAnimation { store.togglePin(tool) }
                } label: {
                    Label(store.isPinned(tool) ? "Открепить" : "Закрепить",
                          systemImage: store.isPinned(tool) ? "star.slash" : "star")
                }
                .tint(.orange)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if tool.isImplemented {
                    Button {
                        path.append(ToolRoute(tool: tool, autostart: true))
                    } label: {
                        Label("Запустить", systemImage: "play.fill")
                    }
                    .tint(.green)
                }
                Button {
                    path.append(ToolRoute(tool: tool, openSettings: true))
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

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: tool.systemImage)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(tool.isImplemented ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if showSubtitle {
                    Text(tool.subtitle)
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
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

/// Routes a tool to its screen (implemented or a coming-soon scaffold).
struct ToolDestinationView: View {
    let route: ToolRoute

    var body: some View {
        switch route.tool {
        case .ping:
            PingView(autostart: route.autostart, openSettings: route.openSettings, presetHost: route.presetHost)
        case .traceroute:
            TracerouteView(presetHost: route.presetHost, autostart: route.autostart)
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
