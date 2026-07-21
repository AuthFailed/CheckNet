import SwiftUI
import Charts
import NetworkKit

struct SpeedTestView: View {
    @State private var model = SpeedTestModel()
    @State private var showServerPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                serverCard
                switch model.phase {
                case .running, .done:
                    gaugeCard
                    if !model.samples.isEmpty { chartCard }
                case .failed(let msg):
                    ErrorBanner(message: msg)
                default:
                    EmptyView()
                }
            }
            .padding(16)
            .animation(.snappy, value: model.phase)
        }
        .background(Palette.groupedBackground)
        .navigationTitle("Тест скорости")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) { bottomBar }
        .task { await model.loadServers() }
        .sheet(isPresented: $showServerPicker) {
            ServerPickerView(model: model)
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

    private var serverStatusText: String {
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
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(model.liveDirection == .download ? .blue : .green)
                        .contentTransition(.numericText())
                    let dirLabel: LocalizedStringKey = model.liveDirection == .download ? "Загрузка" : "Отдача"
                    (Text(dirLabel) + Text(verbatim: " · Мбит/с"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack {
                resultCell(title: "Загрузка", value: model.downloadMbps, color: .blue, icon: "arrow.down")
                Divider().frame(height: 44)
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
            .frame(height: 120)
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

    var body: some View {
        NavigationStack {
            List {
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
                ForEach(model.serverGroups) { group in
                    Section("\(group.title) (\(group.servers.count))") {
                        ForEach(group.servers.prefix(40)) { server in
                            serverRow(server)
                        }
                    }
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
