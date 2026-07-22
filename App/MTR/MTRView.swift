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
    /// At accessibility text sizes a seven-column table cannot work on a phone:
    /// every heading wraps to three lines and the host column shreds into
    /// fragments. Past that threshold each hop becomes a stacked card instead.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ToolScaffold {
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
        } content: {
            if !model.hops.isEmpty {
                tableCard
            }
        } bottom: {
            RunButton(title: "Запустить MTR", running: model.isRunning,
                      disabled: model.host.trimmingCharacters(in: .whitespaces).isEmpty) { model.toggle() }
        }
        .animation(.snappy, value: model.hops)
        .navigationTitle("MTR")
        .toolTitleDisplayMode()
        .onAppear {
            if let presetHost { model.host = presetHost }
            if autostart { model.start() }
        }
    }

    /// A Grid, not a stack of fixed-width columns.
    ///
    /// The table used to hand-align six columns with `.frame(width: 38)` and
    /// 8–9 pt hardcoded fonts. Grid measures each column from its widest cell,
    /// so the numbers stay aligned when Dynamic Type grows them instead of
    /// being clipped, and the whole thing still fits without magic numbers.
    @ViewBuilder
    private var tableCard: some View {
        if typeSize.isAccessibilitySize {
            stackedHops
        } else {
            gridTable
        }
    }

    /// One card per hop, label above value — readable at any text size.
    private var stackedHops: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.hops.enumerated()), id: \.element.ttl) { idx, hop in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(hop.ttl)")
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(hop.reachedDestination ? .green : .secondary)
                        Text(hop.host ?? "*")
                            .font(.caption.monospaced())
                            .foregroundStyle(hop.host == nil ? .secondary : .primary)
                    }
                    if let name = hop.hostname {
                        Text(name).font(.caption).foregroundStyle(.secondary)
                    }
                    stackedStat("Loss", String(format: "%.0f%%", hop.lossPercent),
                                tint: hop.lossPercent > 0 ? .orange : nil)
                    stackedStat("Avg", hop.average.map { String(format: "%.0f", $0) } ?? "—")
                    stackedStat("Best", hop.best.map { String(format: "%.0f", $0) } ?? "—")
                    stackedStat("Wrst", hop.worst.map { String(format: "%.0f", $0) } ?? "—")
                    stackedStat("Last", hop.last.map { String(format: "%.0f", $0) } ?? "—")
                    Text("отпр. \(hop.sent) · получ. \(hop.received)")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                if idx < model.hops.count - 1 { Divider() }
            }
        }
        .padding(12)
        .card()
    }

    private func stackedStat(_ label: LocalizedStringKey, _ value: String, tint: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(tint ?? .primary)
        }
        .font(.caption.monospaced())
    }

    private var gridTable: some View {
        Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text("#").gridColumnAlignment(.leading)
                Text("Хост").gridColumnAlignment(.leading)
                Text("Loss")
                Text("Avg")
                Text("Best")
                Text("Wrst")
                Text("Last")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            Divider().gridCellUnsizedAxes(.horizontal).gridCellColumns(7)

            ForEach(Array(model.hops.enumerated()), id: \.element.ttl) { idx, hop in
                hopRow(hop)
                if idx < model.hops.count - 1 {
                    Divider().gridCellUnsizedAxes(.horizontal).gridCellColumns(7)
                }
            }
        }
        .padding(12)
        .card()
    }

    private func hopRow(_ hop: MTRHop) -> some View {
        GridRow {
            Text("\(hop.ttl)")
                .font(.caption2.monospaced())
                .foregroundStyle(hop.reachedDestination ? .green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(hop.host ?? "*")
                    .font(.caption2.monospaced())
                    .foregroundStyle(hop.host == nil ? .secondary : .primary)
                    .lineLimit(1)
                if let name = hop.hostname {
                    // Semantic font plus a lighter colour for the hierarchy —
                    // 9 pt and 8 pt literals ignored Dynamic Type entirely.
                    Text(name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Text("отпр. \(hop.sent) · получ. \(hop.received)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "%.0f%%", hop.lossPercent))
                .font(.caption2.monospaced())
                .foregroundStyle(hop.lossPercent > 0 ? .orange : .secondary)
            Text(hop.average.map { String(format: "%.0f", $0) } ?? "—")
                .font(.caption2.monospaced())
            Text(hop.best.map { String(format: "%.0f", $0) } ?? "—")
                .font(.caption2.monospaced()).foregroundStyle(.secondary)
            Text(hop.worst.map { String(format: "%.0f", $0) } ?? "—")
                .font(.caption2.monospaced()).foregroundStyle(.secondary)
            Text(hop.last.map { String(format: "%.0f", $0) } ?? "—")
                .font(.caption2.monospaced()).foregroundStyle(.secondary)
        }
    }
}
