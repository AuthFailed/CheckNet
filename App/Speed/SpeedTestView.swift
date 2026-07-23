import SwiftUI
import Charts
import NetworkKit

struct SpeedTestView: View {
    @State private var model = SpeedTestModel()
    @ScaledMetric(relativeTo: .body) private var statRule: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 120
    @State private var showServerPicker = false

    var body: some View {
        ToolScaffold {
            serverCard
            switch model.phase {
            case .running, .done:
                gaugeCard
            case .failed(let msg):
                ErrorCard(message: msg) { model.startTest() }
            default:
                EmptyView()
            }
        } content: {
            switch model.phase {
            case .running, .done:
                if !model.samples.isEmpty { chartCard }
            case .idle, .ready:
                ToolIdleHint(
                    icon: "speedometer",
                    title: "Готово к замеру скорости",
                    message: "Измерим скорость до выбранного сервера: загрузку, отдачу и задержку под нагрузкой."
                )
            default:
                EmptyView()
            }
        } bottom: {
            bottomBar
        }
        .animation(.snappy, value: model.phase)
        .haptic(.success, trigger: model.phase) { $0 == .done }
        .haptic(.failure, trigger: model.phase) { if case .failed = $0 { true } else { false } }
        .navigationTitle("Тест скорости")
        .toolTitleDisplayMode()
        .task { await model.loadServers() }
        .sheet(isPresented: $showServerPicker) {
            // A long, searchable server list grouped by geography — half height
            // would show two rows.
            ServerPickerView(model: model)
                .presentationDetents([.large])
        }
    }

    // MARK: Server selection

    private var serverCard: some View {
        Button {
            showServerPicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "server.rack").foregroundStyle(.tint).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    if let s = model.selected {
                        Text(s.locationLabel.isEmpty ? s.host : s.locationLabel)
                            .font(.callout.weight(.medium)).foregroundStyle(.primary)
                        HStack(spacing: 6) {
                            Text(s.host).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                            if let bw = s.bandwidthValue {
                                Text("· \(bw) Гбит/с").font(.caption).foregroundStyle(.secondary)
                            }
                            if let ping = model.pings[s.host] {
                                Text("· \(Int(ping)) мс").font(.caption).foregroundStyle(.green)
                            }
                        }
                    } else {
                        Text(serverStatusText).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .card()
        }
        .buttonStyle(.plain)
        .disabled(model.phase == .running)
    }

    private var serverStatusText: LocalizedStringKey {
        switch model.phase {
        case .loadingServers: return "Загрузка серверов…"
        case .pinging: return "Проверка серверов \(model.pingProgress.done)/\(model.pingProgress.total)…"
        default: return "Выберите сервер"
        }
    }

    // MARK: Gauge

    private var gaugeCard: some View {
        VStack(spacing: 16) {
            if !model.currentPhaseLabel.isEmpty {
                Text(LocalizedStringKey(model.currentPhaseLabel)).font(.caption).foregroundStyle(.secondary)
            }
            if model.phase == .running {
                VStack(spacing: 4) {
                    Text(String(format: "%.1f", model.liveMbps))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(model.liveDirection == .download ? .blue : .green)
                        .contentTransition(.numericText())
                    let dirLabel: LocalizedStringKey = model.liveDirection == .download ? "Загрузка" : "Отдача"
                    // Interpolation rather than Text + Text: concatenation is
                    // deprecated on macOS 26, and this keeps the unit out of the
                    // translated part of the string.
                    Text("\(Text(dirLabel)) · Мбит/с")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack {
                resultCell(title: "Загрузка", value: model.downloadMbps, color: .blue, icon: "arrow.down")
                Divider().frame(height: statRule)
                resultCell(title: "Отдача", value: model.uploadMbps, color: .green, icon: "arrow.up")
            }
        }
        .padding(16).card()
    }

    private func resultCell(title: String, value: Double?, color: Color, icon: String) -> some View {
        VStack(spacing: 3) {
            Label(LocalizedStringKey(title), systemImage: icon).font(.caption2).foregroundStyle(.secondary)
            Text(value.map { String(format: "%.1f", $0) } ?? "—")
                .font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(color)
            Text("Мбит/с").font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: "Скорость · Мбит/с")
            Chart(Array(model.samples.enumerated()), id: \.offset) { _, sample in
                LineMark(x: .value("t", sample.seconds), y: .value("mbps", sample.mbps))
                    .foregroundStyle(sample.direction == .download ? Color.blue : Color.green)
                    .interpolationMethod(.monotone)
            }
            .frame(height: chartHeight)
        }
        .padding(16).card()
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        RunButton(title: "Запустить тест", running: model.phase == .running,
                  disabled: model.selected == nil) {
            if model.phase == .running { model.stop() } else { model.startTest() }
        }
    }
}

/// Server picker: sorted by measured latency, with a re-check action.
struct ServerPickerView: View {
    @Bindable var model: SpeedTestModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    /// The list caps each group at 40 rows, so without search a specific city
    /// far down the list is simply unreachable. A query filters by city or host
    /// and lifts the cap, since the match is what the user is after.
    private var filteredGroups: [(id: String, title: String, servers: [IperfServer])] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return model.serverGroups.compactMap { group in
            let servers = trimmed.isEmpty
                ? Array(group.servers.prefix(40))
                : group.servers.filter {
                    $0.locationLabel.localizedCaseInsensitiveContains(trimmed)
                    || $0.host.localizedCaseInsensitiveContains(trimmed)
                }
            return servers.isEmpty ? nil : (group.id, group.title, servers)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        Button {
                            Task { await model.pingServers() }
                        } label: {
                            Label(model.phase == .pinging
                                  ? "Проверка \(model.pingProgress.done)/\(model.pingProgress.total)…"
                                  : "Проверить доступность и пинг", systemImage: "bolt.horizontal")
                        }
                        .disabled(model.phase == .pinging)
                        Button {
                            Task { await model.refreshServers() }
                        } label: {
                            Label("Обновить список серверов", systemImage: "arrow.clockwise")
                        }
                        .disabled(model.phase == .pinging || model.phase == .loadingServers)
                    }
                }
                ForEach(filteredGroups, id: \.id) { group in
                    Section("\(group.title) (\(group.servers.count))") {
                        ForEach(group.servers) { server in
                            serverRow(server)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Город или адрес сервера")
            .overlay {
                if !query.isEmpty && filteredGroups.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Серверы iperf3")
            #if os(iOS)
            .toolbarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }

    private func serverRow(_ server: IperfServer) -> some View {
        Button {
            model.selected = server
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.locationLabel.isEmpty ? server.host : server.locationLabel)
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(server.host).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        if let bw = server.bandwidthValue {
                            Text("\(bw) Гбит/с")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(.blue.opacity(0.12), in: Capsule())
                        }
                    }
                }
                Spacer()
                if let ping = model.pings[server.host] {
                    Text("\(Int(ping)) мс")
                        .font(.callout.monospaced())
                        .foregroundStyle(ping < 80 ? .green : (ping < 200 ? .orange : .secondary))
                } else if model.phase == .pinging {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
                if model.selected?.id == server.id {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
