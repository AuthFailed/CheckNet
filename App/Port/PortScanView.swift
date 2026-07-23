import SwiftUI
import NetworkKit

@MainActor
@Observable
final class PortScanModel {
    enum Mode: String, CaseIterable, Identifiable { case common = "Частые", range = "Диапазон"; var id: String { rawValue } }

    var host = "scanme.nmap.org"
    var mode: Mode = .common
    var rangeStart = 1
    var rangeEnd = 1024

    private(set) var isRunning = false
    private(set) var openPorts: [PortCheckResult] = []
    private(set) var scanned = 0
    private(set) var total = 0
    private(set) var errorMessage: String?
    private var task: Task<Void, Never>?
    var useLiveActivity = true

    private let scanner = PortScanner()

    var ports: [Int] {
        switch mode {
        case .common: return PortScanner.commonPorts
        case .range: return Array(min(rangeStart, rangeEnd)...max(rangeStart, rangeEnd))
        }
    }

    func toggle() { isRunning ? stop() : start() }

    func start() {
        let target = host.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }
        stop()
        openPorts = []
        scanned = 0
        errorMessage = nil
        let list = ports
        total = list.count
        isRunning = true
        let activity = useLiveActivity ? CheckActivityController() : nil
        activity?.start(kind: .portScan, title: target, subtitle: "Порты", view: activityView())
        task = Task { [weak self] in
            guard let self else { return }
            // Resolved once, up front. Every port of a name that does not
            // resolve comes back closed, and "0 открытых портов" reads as a
            // locked-down host rather than as a host that was never reached.
            do {
                _ = try await HostResolver.resolveFirst(host: target, family: .ipv4)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                isRunning = false
                await activity?.end(activityView())
                return
            }
            for await result in scanner.scan(host: target, ports: list, timeout: 1.5) {
                if Task.isCancelled { break }
                scanned += 1
                if result.isOpen {
                    openPorts.append(result)
                    openPorts.sort { $0.port < $1.port }
                }
                await activity?.update(activityView())
            }
            isRunning = false
            await activity?.end(activityView())
        }
    }

    func stop() {
        task?.cancel(); task = nil
        isRunning = false
    }

    private func activityView() -> CheckActivityView {
        ScanActivityContent.view(foundLabel: "Открыто", found: openPorts.count,
                                 scanned: scanned, total: total, isRunning: isRunning)
    }
}

struct PortScanView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var model = PortScanModel()
    @Environment(AppSettings.self) private var settings
    @State private var showConsent = false

    private func requestStart() {
        if settings.consentNeeded(for: .portScan) { showConsent = true } else { model.start() }
    }

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $model.host, placeholder: "Хост или IP",
                         icon: "square.grid.3x3.middle.filled", disabled: model.isRunning,
                         savedHostTool: .portScan) {
                model.start()
            }
            modeCard
            if let error = model.errorMessage {
                ErrorCard(message: error) { requestStart() }
            } else if model.total > 0 {
                progressCard
            }
        } content: {
            if !model.openPorts.isEmpty {
                resultsCard
            } else if !model.isRunning && model.scanned > 0 {
                Text("Открытых портов не найдено")
                    .foregroundStyle(.secondary).padding(.top, 24)
            } else if !model.isRunning, model.errorMessage == nil {
                ToolIdleHint(
                    icon: "square.grid.3x3.middle.filled",
                    title: "Готово к проверке портов",
                    message: "Проверим, какие порты хоста принимают соединения, и подпишем известные службы.",
                    example: "scanme.nmap.org",
                    current: model.host
                ) { model.host = "scanme.nmap.org" }
            }
        } bottom: {
            RunButton(title: "Сканировать", running: model.isRunning,
                      disabled: model.host.trimmingCharacters(in: .whitespaces).isEmpty) {
                if model.isRunning { model.stop() } else { requestStart() }
            }
        }
        .animation(.snappy, value: model.openPorts)
        // A check runs for seconds; people put the phone down while it does.
        .haptic(.success, trigger: model.isRunning) { !$0 && model.errorMessage == nil }
        .haptic(.failure, trigger: model.isRunning) { !$0 && model.errorMessage != nil }
        .navigationTitle("Проверка портов")
        .toolTitleDisplayMode()
        .sensitiveConsent(.portScan, isPresented: $showConsent) { model.start() }
        .onAppear {
            model.useLiveActivity = settings.liveActivitiesEnabled
            if let presetHost { model.host = presetHost }
            if autostart { requestStart() }
        }
    }

    private var modeCard: some View {
        VStack(spacing: 10) {
            Picker("Режим", selection: $model.mode) {
                ForEach(PortScanModel.Mode.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(model.isRunning)

            if model.mode == .range {
                HStack {
                    Stepper(value: $model.rangeStart, in: 1...65535) {
                        Text("От \(model.rangeStart)").monospacedDigit()
                    }
                }
                Stepper(value: $model.rangeEnd, in: 1...65535) {
                    Text("До \(model.rangeEnd)").monospacedDigit()
                }
            }
        }
        .padding(14)
        .card()
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(model.openPorts.count) открыто")
                    .font(.headline).foregroundStyle(.green)
                Spacer()
                Text("\(model.scanned) / \(model.total)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(model.scanned), total: Double(max(model.total, 1)))
                .tint(.blue)
        }
        .padding(14)
        .card()
    }

    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: "Открытые порты")
            VStack(spacing: 0) {
                ForEach(Array(model.openPorts.enumerated()), id: \.element.port) { idx, port in
                    HStack {
                        StatusDot(level: .ok, label: "Порт открыт")
                        Text("\(port.port)").font(.system(.body, design: .monospaced)).bold()
                        if let svc = port.serviceName {
                            Text(svc).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let lat = port.latencyMillis {
                            Text("\(String(format: "%.0f", lat)) мс")
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    if idx < model.openPorts.count - 1 { Divider().padding(.leading, 14) }
                }
            }
            .card()
        }
    }
}
