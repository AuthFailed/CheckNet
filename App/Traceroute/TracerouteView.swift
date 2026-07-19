import SwiftUI
import NetworkKit

@MainActor
@Observable
final class TracerouteModel {
    var host = "cloudflare.com"
    var resolveNames = true
    private(set) var isRunning = false
    private(set) var resolvedIP = ""
    private(set) var hops: [TracerouteHop] = []
    private(set) var reached = false
    private var task: Task<Void, Never>?

    func toggle() { isRunning ? stop() : start() }

    func start() {
        let target = host.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }
        stop()
        hops = []; reached = false; resolvedIP = ""; isRunning = true
        let cfg = TracerouteConfig(maxHops: 30, probesPerHop: 3, timeout: 1.5, resolveNames: resolveNames)
        task = Task { [weak self] in
            guard let self else { return }
            for await event in Traceroute().trace(host: target, config: cfg) {
                if Task.isCancelled { break }
                switch event {
                case .started(let ip, _): resolvedIP = ip
                case .hop(let hop): hops.append(hop)
                case .finished(let r): reached = r
                }
            }
            isRunning = false
        }
    }

    func stop() { task?.cancel(); task = nil; isRunning = false }
}

struct TracerouteView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var model = TracerouteModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HostInputBar(text: $model.host, placeholder: "Хост или IP",
                             icon: "point.topleft.down.to.point.bottomright.curvepath",
                             disabled: model.isRunning, savedHostTool: .traceroute) { model.start() }

                Toggle("Разрешать имена (rDNS)", isOn: $model.resolveNames)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .card()
                    .disabled(model.isRunning)

                if !model.resolvedIP.isEmpty {
                    statusRow
                }
                if !model.hops.isEmpty {
                    hopsCard
                }
            }
            .padding(16)
            .animation(.snappy, value: model.hops)
        }
        .background(Palette.groupedBackground)
        .navigationTitle("Трассировка")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) {
            RunButton(title: "Трассировать", running: model.isRunning,
                      disabled: model.host.trimmingCharacters(in: .whitespaces).isEmpty) {
                model.toggle()
            }
        }
        .onAppear {
            if let presetHost { model.host = presetHost }
            if autostart { model.start() }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            if model.isRunning {
                ProgressView().controlSize(.small)
                Text("Трассировка \(model.resolvedIP)…").foregroundStyle(.secondary)
            } else {
                Image(systemName: model.reached ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(model.reached ? .green : .orange)
                Text(model.reached ? "Достигнут за \(model.hops.count) хопов" : "Цель не достигнута")
            }
            Spacer()
        }
        .font(.subheadline)
        .padding(14)
        .card()
    }

    private var hopsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.hops.enumerated()), id: \.element.ttl) { idx, hop in
                hopRow(hop)
                if idx < model.hops.count - 1 { Divider().padding(.leading, 44) }
            }
        }
        .card()
    }

    private func hopRow(_ hop: TracerouteHop) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(hop.ttl)")
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundStyle(hop.reachedDestination ? .green : .secondary)
                .frame(width: 24, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                if hop.isTimeout {
                    Text("* * *").foregroundStyle(.secondary).font(.system(.callout, design: .monospaced))
                } else {
                    Text(hop.routerIP ?? "*")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(hop.reachedDestination ? .green : .primary)
                        .textSelection(.enabled)
                    if let name = hop.hostname {
                        Text(name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(Array(hop.probes.enumerated()), id: \.offset) { _, probe in
                    Text(probe.rttMillis.map { String(format: "%.0f", $0) } ?? "*")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(probe.responded ? .secondary : Color.orange)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}
