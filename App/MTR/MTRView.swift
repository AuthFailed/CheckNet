import SwiftUI
import NetworkKit

@MainActor
@Observable
final class MTRModel {
    var host = "cloudflare.com"
    private(set) var isRunning = false
    private(set) var resolvedIP = ""
    private(set) var hops: [MTRHop] = []
    private(set) var round = 0
    private var task: Task<Void, Never>?

    func toggle() { isRunning ? stop() : start() }

    func start() {
        let target = host.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }
        stop()
        hops = []; round = 0; resolvedIP = ""; isRunning = true
        task = Task { [weak self] in
            guard let self else { return }
            for await event in MTRSession().run(host: target, config: .init(interval: 1.0, resolveNames: true)) {
                if Task.isCancelled { break }
                switch event {
                case .started(let ip): resolvedIP = ip
                case .update(let h, let r): hops = h; round = r
                case .finished: break
                }
            }
            isRunning = false
        }
    }

    func stop() { task?.cancel(); task = nil; isRunning = false }
}

struct MTRView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var model = MTRModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HostInputBar(text: $model.host, placeholder: "Хост или IP", icon: "chart.line.uptrend.xyaxis",
                             disabled: model.isRunning, savedHostTool: .mtr) { model.start() }

                if !model.resolvedIP.isEmpty {
                    HStack {
                        Text(model.resolvedIP).font(.subheadline.monospaced())
                        Spacer()
                        if model.isRunning { Text("Раунд \(model.round)").font(.caption).foregroundStyle(.secondary) }
                    }
                    .padding(.horizontal, 4)
                }

                if !model.hops.isEmpty {
                    tableCard
                }
            }
            .padding(16)
            .animation(.snappy, value: model.hops)
        }
        .background(Palette.groupedBackground)
        .navigationTitle("MTR")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) {
            RunButton(title: "Запустить MTR", running: model.isRunning,
                      disabled: model.host.trimmingCharacters(in: .whitespaces).isEmpty) { model.toggle() }
        }
        .onAppear {
            if let presetHost { model.host = presetHost }
            if autostart { model.start() }
        }
    }

    private var tableCard: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ForEach(Array(model.hops.enumerated()), id: \.element.ttl) { idx, hop in
                hopRow(hop)
                if idx < model.hops.count - 1 { Divider().padding(.leading, 12) }
            }
        }
        .card()
    }

    private let col: CGFloat = 38

    private var header: some View {
        HStack(spacing: 3) {
            Text("#").frame(width: 18, alignment: .leading)
            Text("Хост").frame(maxWidth: .infinity, alignment: .leading)
            Text("Loss").frame(width: col, alignment: .trailing)
            Text("Avg").frame(width: col, alignment: .trailing)
            Text("Best").frame(width: col, alignment: .trailing)
            Text("Wrst").frame(width: col, alignment: .trailing)
            Text("Last").frame(width: col, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func hopRow(_ hop: MTRHop) -> some View {
        HStack(spacing: 3) {
            Text("\(hop.ttl)")
                .font(.caption2.monospaced())
                .foregroundStyle(hop.reachedDestination ? .green : .secondary)
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(hop.host ?? "*")
                    .font(.caption2.monospaced())
                    .foregroundStyle(hop.host == nil ? .secondary : .primary)
                    .lineLimit(1)
                if let name = hop.hostname {
                    Text(name).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                Text("отпр. \(hop.sent) · получ. \(hop.received)")
                    .font(.system(size: 8)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "%.0f%%", hop.lossPercent))
                .font(.caption2.monospaced())
                .foregroundStyle(hop.lossPercent > 0 ? .orange : .secondary)
                .frame(width: col, alignment: .trailing)
            Text(hop.average.map { String(format: "%.0f", $0) } ?? "—")
                .font(.caption2.monospaced()).frame(width: col, alignment: .trailing)
            Text(hop.best.map { String(format: "%.0f", $0) } ?? "—")
                .font(.caption2.monospaced()).foregroundStyle(.secondary).frame(width: col, alignment: .trailing)
            Text(hop.worst.map { String(format: "%.0f", $0) } ?? "—")
                .font(.caption2.monospaced()).foregroundStyle(.secondary).frame(width: col, alignment: .trailing)
            Text(hop.last.map { String(format: "%.0f", $0) } ?? "—")
                .font(.caption2.monospaced()).foregroundStyle(.secondary).frame(width: col, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}
