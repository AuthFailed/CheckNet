import SwiftUI
import Charts
import NetworkKit

struct PingView: View {
    var autostart: Bool = false
    var openSettings: Bool = false
    var presetHost: String? = nil

    @Environment(SavedHostsStore.self) private var savedHosts
    @Environment(AppSettings.self) private var settings
    @Environment(WebhookSettings.self) private var webhooks
    @State private var model = PingViewModel()
    @State private var showSettings = false
    @State private var showWebhookFields = false
    @State private var showSchedule = false
    @State private var showSavePrompt = false
    @State private var showIntermediate = false
    @FocusState private var hostFieldFocused: Bool
    /// Column rules scale with the numbers they separate.
    @ScaledMetric(relativeTo: .body) private var statRule: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var smallRule: CGFloat = 30
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 120

    var body: some View {
        // Per the design: the host field and the verdict live in the leading
        // column; the chart and the packet list are grid modules beside them.
        ToolScaffold {
            hostCard
            if case .finished = model.phase { summaryHeaderCard }
            if case .running = model.phase { liveMeterCard }
        } content: {
            switch model.phase {
            case .idle:
                idleHint
            case .running:
                if !model.replies.isEmpty { responsesCard }
            case .finished:
                if model.stats.rttSamples.count > 1 { latencyChartCard }
                if !model.replies.isEmpty { intermediateDisclosure }
            case .failed(let message):
                failureCard(message)
            }
        } bottom: {
            bottomBar
        }
        .animation(.snappy(duration: 0.28), value: model.phase)
        // A check runs for seconds; people put the phone down while it does.
        .haptic(.success, trigger: model.phase) { if case .finished = $0 { true } else { false } }
        .haptic(.failure, trigger: model.phase) { if case .failed = $0 { true } else { false } }
        .navigationTitle("Ping")
        .toolTitleDisplayMode()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3").accessibilityLabel("Настройки теста")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showSchedule = true } label: {
                    Image(systemName: "clock.arrow.2.circlepath").accessibilityLabel("Расписание")
                }
            }
            // Next to the settings button, only when webhooks are on: what this
            // test sends.
            if webhooks.isEnabled {
                ToolbarItem(placement: .primaryAction) {
                    Button { showWebhookFields = true } label: {
                        Image(systemName: "paperplane").accessibilityLabel("Данные вебхука для этого теста")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            PingSettingsView(model: model)
        }
        .sheet(isPresented: $showWebhookFields) {
            NavigationStack { WebhookFieldsView(schema: WebhookCatalog.ping) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSchedule) {
            NavigationStack {
                Form {
                    SchedulingSection(
                        makeKind: {
                            let host = model.host.trimmingCharacters(in: .whitespaces)
                            return host.isEmpty ? nil : .ping(host: host)
                        },
                        matches: { task in
                            if case .ping(let h) = task.kind {
                                return h.caseInsensitiveCompare(model.host.trimmingCharacters(in: .whitespaces)) == .orderedSame
                            }
                            return false
                        }
                    )
                }
                .navigationTitle("Расписание Ping")
                #if os(iOS)
                .toolbarTitleDisplayMode(.inline)
                #endif
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { showSchedule = false } } }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Сохранить хост", isPresented: $showSavePrompt) {
            Button("Сохранить") { savedHosts.add(name: model.host, value: model.host, tool: .ping) }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(model.host)
        }
        .onAppear {
            model.useLiveActivity = settings.liveActivitiesEnabled
            if let presetHost, !presetHost.isEmpty { model.host = presetHost }
            if openSettings { showSettings = true }
            if autostart { model.start() }
        }
    }

    // MARK: Host card

    private var hostCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
                .font(.title3)
            TextField("Хост или IP", text: $model.host)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($hostFieldFocused)
                .submitLabel(.go)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .onSubmit { model.start() }
                .disabled(model.isRunning)

            if model.isRunning {
                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                        .modifier(PulseModifier())
                        .accessibilityHidden(true)
                    Text("Идёт").font(.caption.weight(.semibold)).foregroundStyle(.blue)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Проверка выполняется")
            } else {
                savedHostsMenu
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .card()
    }

    private var savedHostsMenu: some View {
        Menu {
            let hosts = savedHosts.hosts(for: .ping)
            if !hosts.isEmpty {
                Section("Сохранённые") {
                    ForEach(hosts) { h in
                        Button {
                            model.host = h.value
                        } label: {
                            Label("\(h.name) · \(h.value)", systemImage: "star.fill")
                        }
                    }
                }
            }
            Button {
                showSavePrompt = true
            } label: {
                Label("Сохранить \(model.host)…", systemImage: "plus")
            }
            .disabled(model.host.trimmingCharacters(in: .whitespaces).isEmpty)
        } label: {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(.blue)
                .padding(7)
                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    // MARK: Idle

    private var idleHint: some View {
        ToolIdleHint(
            icon: "dot.radiowaves.left.and.right",
            title: "Готово к проверке",
            message: "Проверьте задержку, потери пакетов и джиттер до любого хоста.",
            example: "1.1.1.1",
            current: model.host
        ) { model.host = "1.1.1.1" }
    }

    // MARK: Live

    @ViewBuilder
    private var liveResults: some View {
        liveMeterCard
        if !model.replies.isEmpty {
            responsesCard
        }
    }

    private var liveMeterCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                PulseRing(value: model.lastRTT)
                VStack(alignment: .leading, spacing: 6) {
                    Group {
                        if let rtt = model.lastRTT {
                            Text("Текущий отклик · \(fmt(rtt)) мс")
                        } else {
                            Text("Ожидание ответа…")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    if model.lastRTT == nil, let err = model.lastError {
                        Text(LocalizedStringKey(err))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    } else {
                        Sparkline(values: model.sparkline)
                            .frame(height: statRule)
                    }
                }
            }
            Divider()
            HStack {
                statCell(value: "\(model.stats.received)/\(model.stats.transmitted)", label: "получено")
                Divider().frame(height: statRule)
                statCell(value: "\(fmt(model.stats.lossPercent))%", label: "потери",
                         color: model.stats.lossPercent > 0 ? .orange : .green)
                Divider().frame(height: statRule)
                statCell(value: model.stats.avg.map { fmt($0) } ?? "—", label: "средн., мс")
            }
        }
        .padding(16)
        .card()
    }

    private var responsesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ОТВЕТЫ")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.bottom, 7).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(model.replies.prefix(8).enumerated()), id: \.element.sequence) { idx, reply in
                    replyRow(reply, dim: idx > 3)
                    if idx < min(7, model.replies.count - 1) { Divider() }
                }
            }
            .card()
        }
    }

    private func replyRow(_ reply: PingReply, dim: Bool) -> some View {
        HStack {
            Text(replyLine(reply))
                .font(.caption.monospaced())
                .foregroundStyle(dim ? .secondary : .primary)
            Spacer()
        }
        .padding(.vertical, 9).padding(.horizontal, 14)
    }

    private func replyLine(_ reply: PingReply) -> String {
        if model.probeType == .tcp {
            return "tcp :\(model.tcpPort) · seq=\(reply.sequence) · \(fmt(reply.rttMillis)) мс"
        }
        let ttl = reply.ttl.map { "ttl=\($0) · " } ?? ""
        return "\(reply.bytes) Б · seq=\(reply.sequence) · \(ttl)\(fmt(reply.rttMillis)) мс"
    }

    // MARK: Summary

    /// What the image export contains: the result, without the host field or
    /// the run button, which mean nothing outside the app.
    @MainActor private var snapshotCard: some View {
        VStack(spacing: 14) {
            summaryHeaderCard
            if model.stats.rttSamples.count > 1 { latencyChartCard }
        }
    }

    /// Deliberately not wrapped in a VStack: the scaffold arranges these, so on
    /// a wide window they flow into columns instead of arriving as one tall item.
    @ViewBuilder
    private var summaryResults: some View {
        summaryHeaderCard
        if model.stats.rttSamples.count > 1 { latencyChartCard }
        if !model.replies.isEmpty { intermediateDisclosure }
    }

    private var summaryHeaderCard: some View {
        let reachable = model.stats.received > 0
        return VStack(spacing: 14) {
            HStack(spacing: 11) {
                Image(systemName: reachable ? "checkmark" : "xmark")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(reachable ? Color.green : Color.red, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(reachable ? LocalizedStringKey("Хост доступен") : LocalizedStringKey("Хост недоступен"))
                        .font(.title3.weight(.bold))
                    Text("\(model.stats.received) из \(model.stats.transmitted) · \(fmt(model.stats.lossPercent))% потерь · \(fmt(model.elapsedSeconds)) с")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let name = model.reverseName {
                HStack {
                    Image(systemName: "arrow.uturn.backward").font(.caption).foregroundStyle(.secondary)
                    Text(name).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            Divider()
            HStack {
                statCell(value: model.stats.min.map { fmt($0) } ?? "—", label: "мин")
                Divider().frame(height: smallRule)
                statCell(value: model.stats.avg.map { fmt($0) } ?? "—", label: "средн.", color: .blue)
                Divider().frame(height: smallRule)
                statCell(value: model.stats.max.map { fmt($0) } ?? "—", label: "макс")
                Divider().frame(height: smallRule)
                statCell(value: model.stats.jitter.map { fmt($0) } ?? "—", label: "джиттер")
            }
        }
        .padding(16)
        .card()
    }

    private var latencyChartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ЗАДЕРЖКА · МС")
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Chart(Array(model.rttSeries.enumerated()), id: \.offset) { idx, value in
                LineMark(x: .value("seq", idx), y: .value("ms", value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.blue)
                AreaMark(x: .value("seq", idx), y: .value("ms", value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(colors: [.blue.opacity(0.25), .blue.opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom))
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .chartXAxis(.hidden)
            .frame(height: chartHeight)
        }
        .padding(16)
        .card()
    }

    private var intermediateDisclosure: some View {
        DisclosureGroup(isExpanded: $showIntermediate) {
            VStack(spacing: 0) {
                ForEach(model.replies, id: \.sequence) { reply in
                    replyRow(reply, dim: false)
                    Divider()
                }
            }
        } label: {
            HStack {
                Image(systemName: "list.bullet").foregroundStyle(.secondary)
                Text("Промежуточные результаты").font(.body)
                Spacer()
                Text("\(model.replies.count) пакетов").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .card()
    }

    // MARK: Failure

    private func failureCard(_ message: String) -> some View {
        ErrorCard(message: message) { model.start() }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if model.phase == .finished {
                // Picture or text — a ping result pasted into a chat as text
                // loses its shape, and a screenshot is what people actually send
                // to support or to an ISP.
                ResultShareMenu(
                    snapshot: { snapshotCard },
                    text: shareText,
                    name: "checknet-ping"
                )
                .font(.headline).frame(maxWidth: .infinity).frame(minHeight: 52)
                .foregroundStyle(.white)
                .background(.blue, in: RoundedRectangle(cornerRadius: 15))
                Button { model.start() } label: {
                    Image(systemName: "arrow.clockwise").font(.title3.weight(.semibold))
                        .frame(width: 52, height: 52)
                        .card()
                }
            } else {
                Button { model.toggle() } label: {
                    Label(model.isRunning ? LocalizedStringKey("Остановить") : LocalizedStringKey("Запустить проверку"),
                          systemImage: model.isRunning ? "stop.fill" : "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).frame(minHeight: 52)
                        .foregroundStyle(model.isRunning ? .red : .white)
                        .background(model.isRunning ? AnyShapeStyle(Color.red.opacity(0.14))
                                                    : AnyShapeStyle(Color.blue),
                                    in: RoundedRectangle(cornerRadius: 15))
                }
                .disabled(model.host.trimmingCharacters(in: .whitespaces).isEmpty)
                // Same hook as RunButton — Ping draws its own control here.
                .accessibilityIdentifier("tool.runButton")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }

    private var shareText: String {
        var lines = ["Ping \(model.host) (\(model.resolvedIP))"]
        lines.append("Получено \(model.stats.received)/\(model.stats.transmitted), потери \(fmt(model.stats.lossPercent))%")
        if let avg = model.stats.avg { lines.append("min/avg/max/jitter = \(fmt(model.stats.min ?? 0))/\(fmt(avg))/\(fmt(model.stats.max ?? 0))/\(fmt(model.stats.jitter ?? 0)) мс") }
        return lines.joined(separator: "\n")
    }

    // MARK: Helpers

    private func statCell(value: String, label: String, color: Color = .primary) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.callout.weight(.bold).monospaced()).foregroundStyle(color)
            Text(LocalizedStringKey(label)).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func fmt(_ v: Double) -> String {
        String(format: v >= 100 ? "%.0f" : "%.1f", v)
    }
}
