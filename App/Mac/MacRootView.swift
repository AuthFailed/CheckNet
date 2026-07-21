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
                Picker("", selection: $mode) {
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
                            row(tool.title, tool.systemImage, soon: !tool.isImplemented)
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
    }

    private func row(_ title: String, _ symbol: String, soon: Bool = false) -> some View {
        HStack(spacing: 8) {
            Label(LocalizedStringKey(title), systemImage: symbol)
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
                ContentUnavailableView(
                    "Выберите инструмент",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("Слева — все проверки, сгруппированные по разделам. Выберите любую, чтобы запустить её.")
                )
            }
        }
    }
}
#endif
