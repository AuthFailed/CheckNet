import SwiftUI
import NetworkKit

@MainActor
@Observable
final class NetworkBrowserModel {
    private(set) var isRunning = false
    private(set) var devices: [DiscoveredDevice] = []
    private(set) var scanned = 0
    private(set) var total = 0
    private(set) var errorMessage: String?
    private var task: Task<Void, Never>?
    var useLiveActivity = true

    func toggle() { isRunning ? stop() : start() }

    private func activityView() -> CheckActivityView {
        ScanActivityContent.view(foundLabel: "Устройств", found: devices.count,
                                 scanned: scanned, total: total, isRunning: isRunning)
    }

    func start() {
        stop()
        devices = []; scanned = 0; total = 0; errorMessage = nil; isRunning = true
        let activity = useLiveActivity ? CheckActivityController() : nil
        activity?.start(kind: .browser, title: "Обзор сети", subtitle: "Устройства", view: activityView())
        task = Task { [weak self] in
            guard let self else { return }
            for await event in NetworkBrowser().browse() {
                if Task.isCancelled { break }
                switch event {
                case .progress(let s, let t): scanned = s; total = t
                case .device(let d):
                    devices.append(d)
                    devices.sort { (IPv4Range.toUInt32($0.ip) ?? 0) < (IPv4Range.toUInt32($1.ip) ?? 0) }
                case .finished: break
                case .failed(let reason): errorMessage = reason
                }
                await activity?.update(activityView())
            }
            isRunning = false
            await activity?.end(activityView())
        }
    }

    func stop() { task?.cancel(); task = nil; isRunning = false }

    /// Restart the sweep and wait for it to finish, so the pull-to-refresh
    /// spinner lasts as long as the scan does.
    func refresh() async {
        start()
        await task?.value
    }
}

struct NetworkBrowserView: View {
    @State private var model = NetworkBrowserModel()
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ToolScaffold {
            if let error = model.errorMessage {
                ErrorCard(message: error) { model.start() }
            } else if model.total > 0 {
                progressCard
            }
            if model.devices.isEmpty, !model.isRunning, model.errorMessage == nil {
                ContentUnavailableView("Обзор сети", systemImage: "rectangle.connected.to.line.below",
                                       description: Text("Найдём устройства в вашей сети с IP, MAC и вендором."))
                .padding(.top, 40)
            }
        } content: {
            if !model.devices.isEmpty {
                devicesCard
            }
        } bottom: {
            RunButton(title: "Сканировать сеть", running: model.isRunning) { model.toggle() }
        }
        .animation(.snappy, value: model.devices)
        .refreshable { await model.refresh() }
        // A check runs for seconds; people put the phone down while it does.
        .haptic(.success, trigger: model.isRunning) { !$0 && model.errorMessage == nil }
        .haptic(.failure, trigger: model.isRunning) { !$0 && model.errorMessage != nil }
        .navigationTitle("Обзор сети")
        .toolTitleDisplayMode()
        .onAppear { model.useLiveActivity = settings.liveActivitiesEnabled }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(model.devices.count) устройств").font(.headline).foregroundStyle(.green)
                Spacer()
                Text("\(model.scanned) / \(model.total)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(model.scanned), total: Double(max(model.total, 1))).tint(.blue)
        }
        .padding(14).card()
    }

    private var devicesCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.devices.enumerated()), id: \.element.id) { idx, device in
                deviceRow(device)
                if idx < model.devices.count - 1 { Divider().padding(.leading, 56) }
            }
        }
        .card()
    }

    private func deviceRow(_ device: DiscoveredDevice) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: device))
                .font(.title3)
                .foregroundStyle(device.isGateway ? .orange : (device.isSelf ? .blue : .secondary))
                .frame(minWidth: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.displayName).font(.callout.weight(.medium)).lineLimit(1)
                    if device.isSelf { tag("вы", .blue) }
                    if device.isGateway { tag("шлюз", .orange) }
                }
                Text(device.ip).font(.caption.monospaced()).foregroundStyle(.secondary)
                if let mac = device.mac {
                    HStack(spacing: 4) {
                        Text(mac).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                        if let vendor = device.vendor {
                            Text("· \(vendor)").font(.caption2).foregroundStyle(.secondary)
                        } else if device.randomizedMAC {
                            Text("· случайный MAC").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            Spacer()
            if let rtt = device.rttMillis {
                Text("\(Int(rtt)) мс").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func icon(for device: DiscoveredDevice) -> String {
        if device.isGateway { return "wifi.router" }
        if device.isSelf { return "iphone" }
        switch device.vendor {
        case .some(let v) where v.contains("Apple"): return "applelogo"
        case .some(let v) where v.contains("Raspberry"): return "cpu"
        case .some(let v) where v.contains("ESP") || v.contains("Espressif"): return "sensor"
        default: return "desktopcomputer"
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(LocalizedStringKey(text))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
    }
}
