#if os(macOS)
import SwiftUI

/// The Mac window: one sidebar, one detail column.
///
/// Previously the Mac inherited the iPhone structure — a `TabView` made
/// adaptive, with a `NavigationSplitView` nested inside each tab. That produced
/// three columns in an 1100 pt window: tabs, tool list, tool. The middle one got
/// whatever was left and collapsed until the user dragged it open.
///
/// Per the macOS design the two sections are a switcher at the top of a single
/// sidebar, so the window is sidebar + detail and the tool always has the room.
struct MacRootView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case tests, blocking
        var id: String { rawValue }
        var title: LocalizedStringKey { self == .tests ? "Тесты" : "Блокировки" }
        var symbol: String { self == .tests ? "wrench.and.screwdriver" : "hand.raised" }
    }

    /// One selectable row, whichever section it came from.
    enum Selection: Hashable {
        case tool(Tool)
        case check(BlockingCheck)
        case reachability
    }

    @Environment(AppSettings.self) private var settings
    @Environment(ToolStore.self) private var store
    @State private var mode: Mode = .tests
    @State private var selection: Selection?
    @State private var query = ""
    /// Last known result per host, so the sidebar reports state instead of
    /// being a static menu. Refreshed when a check finishes writing history.
    @State private var snapshots: [PingSnapshot] = []
    @State private var recent: [CheckRecord] = []

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 262, max: 380)
        } detail: {
            detail
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .environment(\.locale, settings.language.localeIdentifier.map(Locale.init) ?? .current)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                Picker("Раздел", selection: $mode) {
                    ForEach(Mode.allCases) { m in
                        Label(m.title, systemImage: m.symbol).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
            }

            if mode == .tests {
                ForEach(filteredToolSections) { section in
                    Section(LocalizedStringKey(section.title)) {
                        ForEach(section.tools) { tool in
                            row(tool.title, tool.systemImage,
                                soon: !tool.isImplemented, badge: badge(for: tool))
                                .tag(Selection.tool(tool))
                        }
                    }
                }
            } else {
                ForEach(BlockingSection.allCases) { section in
                    if !section.checks.isEmpty {
                        Section(LocalizedStringKey(section.title)) {
                            ForEach(section.checks) { check in
                                row(check.title, check.systemImage)
                                    .tag(Selection.check(check))
                            }
                        }
                    }
                }
                Section {
                    row("Доступность узлов", "globe").tag(Selection.reachability)
                }
            }
        }
        .searchable(text: $query, prompt: "Поиск")
        .navigationTitle("CheckNet")
        .onAppear(perform: reload)
        // Cheap poll rather than a store observer: the checks write through
        // SharedStore from several places, including out-of-process intents.
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            reload()
        }
    }

    private func reload() {
        snapshots = SharedStore.snapshots()
        recent = Array(SharedStore.history(source: .manual).prefix(6))
    }

    /// The most recent result for a tool, shown on its sidebar row.
    private func badge(for tool: Tool) -> (text: String, tint: Color)? {
        guard let record = recent.first(where: { $0.tool == tool.title }) else { return nil }
        if let latency = record.latencyMillis, record.succeeded {
            return (String(format: "%.0f мс", latency), .secondary)
        }
        return record.succeeded ? ("ок", .secondary) : ("сбой", .red)
    }

    private func row(_ title: String, _ symbol: String, soon: Bool = false,
                     badge: (text: String, tint: Color)? = nil) -> some View {
        HStack(spacing: 8) {
            Label(LocalizedStringKey(title), systemImage: symbol)
            if let badge {
                Spacer(minLength: 6)
                Text(badge.text)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(badge.tint)
            }
            if soon {
                Spacer(minLength: 6)
                Text("скоро")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
    }

    /// Search filters the list in place rather than replacing it with a separate
    /// results screen — in a sidebar the sections are the user's map.
    private var filteredToolSections: [ToolSection] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return ToolCatalog.sections }
        return ToolCatalog.sections.compactMap { section in
            let hits = section.tools.filter {
                $0.title.localizedCaseInsensitiveContains(q)
                    || $0.subtitle.localizedCaseInsensitiveContains(q)
            }
            return hits.isEmpty ? nil : ToolSection(id: section.id, title: section.title, tools: hits)
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        NavigationStack {
            switch selection {
            case .tool(let tool):
                ToolDestinationView(route: ToolRoute(tool: tool)).id(tool)
            case .check(let check):
                BlockingCheckView(check: check).id(check)
            case .reachability:
                ReachabilityView()
            case nil:
                emptyDetail
            }
        }
    }

    /// Not a dead end: a fresh window shows what was checked last, and each row
    /// reopens that tool. It also answers "what do I do first".
    @ViewBuilder
    private var emptyDetail: some View {
        if recent.isEmpty {
            ContentUnavailableView(
                "Выберите инструмент",
                systemImage: "wrench.and.screwdriver",
                description: Text("Слева — все проверки. Выберите любую, чтобы запустить её.")
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Недавние проверки")
                        .font(.title3.weight(.semibold))
                    ForEach(recent) { record in
                        Button {
                            if let tool = Tool.allCases.first(where: { $0.title == record.tool }) {
                                selection = .tool(tool)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: record.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(record.succeeded ? .green : .red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizedStringKey(record.tool)).font(.callout.weight(.medium))
                                    Text(record.host).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let latency = record.latencyMillis {
                                    Text(String(format: "%.0f мс", latency))
                                        .font(.callout.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Text(record.timestamp, style: .time)
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            .card()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .frame(maxWidth: ToolLayout.contentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.groupedBackground)
        }
    }
}
#endif
