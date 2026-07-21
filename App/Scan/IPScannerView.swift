import SwiftUI
import NetworkKit

@MainActor
@Observable
final class IPScannerModel {
    var range = ""
    private(set) var isRunning = false
    private(set) var hosts: [DiscoveredHost] = []
    private(set) var scanned = 0
    private(set) var total = 0
    private var task: Task<Void, Never>?

    init() { range = Self.defaultRange() }

    func toggle() { isRunning ? stop() : start() }

    func start() {
        let r = range.trimmingCharacters(in: .whitespaces)
        guard !r.isEmpty else { return }
        stop()
        hosts = []; scanned = 0; total = 0; isRunning = true
        task = Task { [weak self] in
            guard let self else { return }
            for await event in IPRangeScanner().scan(range: r, timeout: 1.0, resolveNames: true) {
                if Task.isCancelled { break }
                switch event {
                case .progress(let s, let t):
                    scanned = s; total = t
                case .host(let h):
                    hosts.append(h)
                    hosts.sort { (IPv4Range.toUInt32($0.ip) ?? 0) < (IPv4Range.toUInt32($1.ip) ?? 0) }
                case .finished:
                    break
                }
            }
            isRunning = false
        }
    }

    func stop() { task?.cancel(); task = nil; isRunning = false }

    /// Derives a /24 range from the primary local IPv4 interface.
    static func defaultRange() -> String {
        let ifaces = NetworkInterfaces.list(includeLoopback: false, includeIPv6: false)
        if let en = ifaces.first(where: { $0.name.hasPrefix("en") && $0.family == .ipv4 }) ?? ifaces.first {
            let parts = en.address.split(separator: ".")
            if parts.count == 4 { return "\(parts[0]).\(parts[1]).\(parts[2]).0/24" }
        }
        return "192.168.1.0/24"
    }
}

struct IPScannerView: View {
    var autostart = false
    @State private var model = IPScannerModel()
    @Environment(AppSettings.self) private var settings
    @State private var showConsent = false

    private func requestStart() {
        if settings.consentNeeded(for: .ipScanner) { showConsent = true } else { model.start() }
    }

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $model.range, placeholder: "CIDR или диапазон",
                         icon: "barcode.viewfinder", disabled: model.isRunning) { requestStart() }

            if model.total > 0 {
                progressCard
            }
            if !model.hosts.isEmpty {
                hostsCard
            } else if !model.isRunning && model.scanned > 0 {
                Text("Активных хостов не найдено").foregroundStyle(.secondary).padding(.top, 24)
            }
        } bottom: {
            RunButton(title: "Сканировать", running: model.isRunning,
                      disabled: model.range.trimmingCharacters(in: .whitespaces).isEmpty) {
                if model.isRunning { model.stop() } else { requestStart() }
            }
        }
        .animation(.snappy, value: model.hosts)
        .navigationTitle("Сканер диапазона")
        .toolTitleDisplayMode()
        .sensitiveConsent(.ipScanner, isPresented: $showConsent) { model.start() }
        .onAppear { if autostart { requestStart() } }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(model.hosts.count) активных").font(.headline).foregroundStyle(.green)
                Spacer()
                Text("\(model.scanned) / \(model.total)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(model.scanned), total: Double(max(model.total, 1))).tint(.blue)
        }
        .padding(14).card()
    }

    private var hostsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.hosts.enumerated()), id: \.element.id) { idx, host in
                HStack {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(host.ip).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        if let name = host.hostname {
                            Text(name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Text("\(String(format: "%.0f", host.rttMillis)) мс")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                if idx < model.hosts.count - 1 { Divider().padding(.leading, 34) }
            }
        }
        .card()
    }
}
