import SwiftUI
import NetworkKit

@MainActor
@Observable
final class WorldPingModel {
    var host = "google.com"
    var type: WorldProbe.CheckType = .ping
    /// Selected countries; empty means pick nodes at random.
    var selectedCountries: Set<String> = []

    private(set) var nodes: [WorldProbeNode] = []
    private(set) var results: [WorldProbeResult] = []
    private(set) var isRunning = false
    private(set) var errorMessage: String?
    private var task: Task<Void, Never>?

    var reachableCount: Int { results.filter { $0.status == .ok }.count }
    var reportedCount: Int { results.filter { $0.status != .pending }.count }

    /// Countries offered by the backend, for the picker.
    var countries: [(country: String, code: String, count: Int)] {
        var order: [String] = []
        var counts: [String: (code: String, count: Int)] = [:]
        for node in nodes {
            if counts[node.country] == nil { order.append(node.country) }
            counts[node.country, default: (node.countryCode, 0)].count += 1
        }
        return order.map { ($0, counts[$0]!.code, counts[$0]!.count) }
    }

    func loadNodes() async {
        if nodes.isEmpty { nodes = (try? await WorldProbe().availableNodes()) ?? [] }
    }

    func toggle() { isRunning ? stop() : start() }

    func start() {
        let target = host.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }
        stop()
        results = []; errorMessage = nil; isRunning = true
        let type = self.type
        let names = selectedCountries.isEmpty ? [] : nodes.filter { selectedCountries.contains($0.country) }.map(\.name)
        task = Task { [weak self] in
            for await event in WorldProbe().run(type: type, host: target, nodeNames: names) {
                guard let self, !Task.isCancelled else { break }
                switch event {
                case .started(let r): self.results = r
                case .update(let r): self.upsert(r)
                case .finished(let r): self.results = r; self.isRunning = false
                case .failed(let reason): self.errorMessage = reason; self.isRunning = false
                }
            }
            self?.isRunning = false
        }
    }

    func stop() { task?.cancel(); task = nil; isRunning = false }

    private func upsert(_ result: WorldProbeResult) {
        if let i = results.firstIndex(where: { $0.id == result.id }) { results[i] = result }
        else { results.append(result) }
    }
}

struct WorldPingView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var model = WorldPingModel()
    @State private var showNodePicker = false

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $model.host, placeholder: hostPlaceholder, icon: "globe.badge.chevron.backward",
                         disabled: model.isRunning, savedHostTool: .worldPing) { model.start() }
            controlsCard
            if let error = model.errorMessage {
                ErrorCard(message: error) { model.start() }
            } else if !model.results.isEmpty {
                summaryCard
            }
        } content: {
            if model.errorMessage == nil {
                if !model.results.isEmpty {
                    resultsList
                } else if !model.isRunning {
                    ToolIdleHint(
                        icon: "globe.badge.chevron.backward",
                        title: "Доступность со всего мира",
                        message: "Проверим хост с узлов в разных странах — ping, HTTP, TCP, DNS или UDP. Видно, откуда ресурс доступен, а откуда нет. Проверка идёт через внешний сервис.",
                        example: "google.com",
                        current: model.host
                    ) { model.host = "google.com" }
                }
            }
        } bottom: {
            RunButton(title: "Проверить", running: model.isRunning) { model.toggle() }
        }
        .navigationTitle("World Ping")
        .toolTitleDisplayMode()
        .task { await model.loadNodes() }
        .sheet(isPresented: $showNodePicker) {
            NodeSelectionSheet(model: model)
        }
        .onAppear {
            if let presetHost { model.host = presetHost }
            if autostart { model.start() }
        }
    }

    private var hostPlaceholder: String {
        switch model.type {
        case .tcp, .udp: "host:port"
        case .http: "домен или URL"
        default: "домен или IP"
        }
    }

    // MARK: Controls

    private var controlsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Тип проверки").foregroundStyle(.secondary)
                Spacer()
                Picker("Тип проверки", selection: $model.type) {
                    Text("Ping").tag(WorldProbe.CheckType.ping)
                    Text("HTTP").tag(WorldProbe.CheckType.http)
                    Text("TCP-порт").tag(WorldProbe.CheckType.tcp)
                    Text("DNS").tag(WorldProbe.CheckType.dns)
                    Text("UDP-порт").tag(WorldProbe.CheckType.udp)
                }
                .labelsHidden()
                .disabled(model.isRunning)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider().padding(.leading, 14)
            Button { showNodePicker = true } label: {
                HStack {
                    Text("Узлы").foregroundStyle(.secondary)
                    Spacer()
                    Text(nodeSelectionLabel).foregroundStyle(.tint)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .disabled(model.isRunning || model.nodes.isEmpty)
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .card()
    }

    private var nodeSelectionLabel: String {
        if model.selectedCountries.isEmpty { return "Авто" }
        if model.selectedCountries.count == 1 { return model.selectedCountries.first! }
        return "\(model.selectedCountries.count) стран"
    }

    // MARK: Summary

    private var summaryCard: some View {
        let reachable = model.reachableCount
        let total = model.results.count
        let allReported = model.reportedCount == total
        return HStack(spacing: 12) {
            Image(systemName: reachable == total ? "checkmark.circle.fill"
                  : reachable == 0 ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(reachable == total ? .green : reachable == 0 ? .red : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Доступен с \(reachable) из \(total)").font(.headline)
                Text(allReported ? "Проверка завершена" : "Проверка идёт…")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isRunning { ProgressView() }
        }
        .padding(14)
        .card()
    }

    // MARK: Results

    private var resultsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.results.enumerated()), id: \.element.id) { idx, result in
                HStack(spacing: 11) {
                    Text(result.node.flagEmoji ?? "🏳️").font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(result.node.country) · \(result.node.city)").font(.callout)
                        Text(LocalizedStringKey(result.summary)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    statusView(result)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                if idx < model.results.count - 1 { Divider().padding(.leading, 44) }
            }
        }
        .card()
    }

    @ViewBuilder
    private func statusView(_ result: WorldProbeResult) -> some View {
        switch result.status {
        case .pending:
            ProgressView().controlSize(.small)
        case .ok:
            if let rtt = result.rttMillis {
                Text("\(Int(rtt)) мс").font(.callout.monospacedDigit()).foregroundStyle(.green)
            } else {
                StatusDot(level: .ok, label: "Доступен")
            }
        case .failed:
            StatusDot(level: .bad, label: "Недоступен")
        case .error:
            StatusDot(level: .warning, label: "Ошибка")
        }
    }
}

// MARK: - Node selection

private struct NodeSelectionSheet: View {
    @Bindable var model: WorldPingModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var collapsed: Set<String> = []

    private typealias Country = (country: String, code: String, count: Int)

    /// Countries grouped by continent, filtered by the search query, in a fixed
    /// continent order.
    private var groups: [(name: String, countries: [Country])] {
        let filtered = model.countries.filter {
            query.isEmpty || $0.country.localizedCaseInsensitiveContains(query)
        }
        var byContinent: [String: [Country]] = [:]
        for entry in filtered { byContinent[Continent.of(entry.code), default: []].append(entry) }
        return Continent.order.compactMap { name in
            guard let list = byContinent[name], !list.isEmpty else { return nil }
            return (name, list.sorted { $0.country < $1.country })
        }
    }

    private func isExpanded(_ continent: String) -> Bool {
        !query.isEmpty || !collapsed.contains(continent)   // searching expands everything
    }

    private func selectedCount(in countries: [Country]) -> Int {
        countries.filter { model.selectedCountries.contains($0.country) }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { model.selectedCountries = [] } label: {
                        HStack {
                            Label("Случайные узлы по миру", systemImage: "dice")
                            Spacer()
                            if model.selectedCountries.isEmpty {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }

                ForEach(groups, id: \.name) { group in
                    Section {
                        if isExpanded(group.name) {
                            ForEach(group.countries, id: \.country) { entry in
                                countryRow(entry)
                            }
                        }
                    } header: {
                        continentHeader(group)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Поиск страны")
            .navigationTitle("Откуда проверять")
            #if os(iOS)
            .toolbarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !model.selectedCountries.isEmpty {
                        Button("Сбросить") { model.selectedCountries = [] }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func continentHeader(_ group: (name: String, countries: [Country])) -> some View {
        let selected = selectedCount(in: group.countries)
        let allSelected = selected == group.countries.count
        return HStack(spacing: 8) {
            Button {
                if query.isEmpty {
                    if collapsed.contains(group.name) { collapsed.remove(group.name) }
                    else { collapsed.insert(group.name) }
                }
            } label: {
                Image(systemName: isExpanded(group.name) ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.bold)).frame(width: 14)
                Text(group.name).font(.subheadline.weight(.semibold))
                if selected > 0 {
                    Text("\(selected)/\(group.countries.count)").font(.caption).foregroundStyle(.tint)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button(allSelected ? "Снять" : "Все") {
                let names = group.countries.map(\.country)
                if allSelected { names.forEach { model.selectedCountries.remove($0) } }
                else { names.forEach { model.selectedCountries.insert($0) } }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)
        }
        .textCase(nil)
    }

    private func countryRow(_ entry: Country) -> some View {
        Button {
            if model.selectedCountries.contains(entry.country) {
                model.selectedCountries.remove(entry.country)
            } else {
                model.selectedCountries.insert(entry.country)
            }
        } label: {
            HStack(spacing: 10) {
                Text(IPGeoFlag.emoji(entry.code) ?? "🏳️")
                Text(entry.country).foregroundStyle(.primary)
                Text("\(entry.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.selectedCountries.contains(entry.country) {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
    }
}

/// Coarse ISO country-code → continent mapping for grouping the node picker.
enum Continent {
    static let order = ["Европа", "Азия", "Северная Америка", "Южная Америка", "Африка", "Океания", "Другие"]

    static func of(_ code: String) -> String {
        switch code.lowercased() {
        case "at", "be", "bg", "by", "ch", "cz", "de", "dk", "ee", "es", "fi", "fr", "gb", "gr", "hr",
             "hu", "ie", "is", "it", "lt", "lu", "lv", "md", "me", "mk", "nl", "no", "pl", "pt", "ro",
             "rs", "ru", "se", "si", "sk", "ua", "ba", "al", "mt", "cy", "li", "mc", "sm", "va", "ad", "xk":
            return "Европа"
        case "ae", "am", "az", "bd", "bh", "bn", "bt", "cn", "ge", "hk", "id", "il", "in", "iq", "ir",
             "jo", "jp", "kg", "kh", "kr", "kw", "kz", "la", "lb", "lk", "mm", "mn", "mo", "mv", "my",
             "np", "om", "ph", "pk", "qa", "sa", "sg", "sy", "th", "tj", "tm", "tr", "tw", "uz", "vn", "ye":
            return "Азия"
        case "ca", "us", "mx", "cr", "pa", "do", "gt", "hn", "ni", "sv", "jm", "cu", "ht", "bs", "bz",
             "tt", "bb", "pr":
            return "Северная Америка"
        case "ar", "bo", "br", "cl", "co", "ec", "gy", "py", "pe", "sr", "uy", "ve", "gf":
            return "Южная Америка"
        case "dz", "ao", "bj", "bw", "cd", "cg", "ci", "cm", "eg", "et", "gh", "ke", "ma", "mg", "ml",
             "mu", "mz", "ng", "rw", "sc", "sn", "so", "tn", "tz", "ug", "za", "zm", "zw", "sd", "ly",
             "gm", "gn", "bf", "ne", "td", "cf", "ga", "gq", "cv", "dj", "er", "ls", "sz", "na", "bi", "mw":
            return "Африка"
        case "au", "nz", "fj", "pg", "nc", "pf", "ws", "to", "vu", "sb":
            return "Океания"
        default:
            return "Другие"
        }
    }
}

/// Flag emoji from a two-letter code, for the country picker.
enum IPGeoFlag {
    static func emoji(_ code: String) -> String? {
        let cc = code.uppercased()
        guard cc.count == 2, cc.allSatisfy(\.isLetter) else { return nil }
        var result = ""
        for scalar in cc.unicodeScalars {
            guard let flag = UnicodeScalar(0x1F1E6 + scalar.value - 65) else { return nil }
            result.unicodeScalars.append(flag)
        }
        return result
    }
}
