import SwiftUI
import NetworkKit

@MainActor
@Observable
final class MTUModel {
    var host = "1.1.1.1"
    private(set) var isRunning = false
    private(set) var currentProbe: Int?
    private(set) var result: MTUResult?
    private(set) var errorMessage: String?
    private var task: Task<Void, Never>?

    func toggle() { isRunning ? stop() : start() }

    func start() {
        let target = host.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }
        stop()
        result = nil; errorMessage = nil; currentProbe = nil; isRunning = true
        task = Task { [weak self] in
            guard let self else { return }
            for await progress in MTUDiscovery().discover(host: target) {
                if Task.isCancelled { break }
                switch progress {
                case .probing(let payload): currentProbe = payload
                case .finished(let r): result = r
                case .failed(let msg): errorMessage = msg
                }
            }
            isRunning = false
            currentProbe = nil
        }
    }

    func stop() { task?.cancel(); task = nil; isRunning = false }
}

struct MTUView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var model = MTUModel()
    @ScaledMetric(relativeTo: .body) private var statRule: CGFloat = 34

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $model.host, placeholder: "Хост или IP", icon: "ruler",
                         disabled: model.isRunning, savedHostTool: .mtuDiscovery) { model.start() }

            if model.isRunning, let probe = model.currentProbe {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Проба \(probe + 28) байт…").foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(14).card()
            }
            if let error = model.errorMessage {
                ErrorCard(message: error) { model.start() }
            }
        } content: {
            if let result = model.result {
                resultCard(result)
            }
        } bottom: {
            RunButton(title: "Определить MTU", running: model.isRunning,
                      disabled: model.host.trimmingCharacters(in: .whitespaces).isEmpty) {
                model.toggle()
            }
        }
        .animation(.snappy, value: model.result)
        .navigationTitle("MTU discovery")
        .toolTitleDisplayMode()
        .onAppear {
            if let presetHost { model.host = presetHost }
            if autostart { model.start() }
        }
    }

    private func resultCard(_ result: MTUResult) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("\(result.pathMTU)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(.tint)
                    .contentTransition(.numericText())
                Text("Path MTU · байт").font(.subheadline).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                metric("\(result.maxPayload)", "ICMP payload")
                Divider().frame(height: statRule)
                metric("\(result.pathMTU)", "MTU")
                Divider().frame(height: statRule)
                metric("\(result.probes.count)", "проб")
            }
            if result.pathMTU < 1500 {
                Label("Путь ограничивает MTU ниже 1500 — вероятны туннель/VPN/PPPoE.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(16).card()
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(.title3, design: .monospaced).weight(.bold))
            Text(LocalizedStringKey(label)).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
