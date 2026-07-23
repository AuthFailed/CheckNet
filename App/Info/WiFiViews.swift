#if os(macOS)
import SwiftUI
import CoreLocation
import NetworkKit

/// macOS needs Location access before it will hand over the current SSID and a
/// full scan. RF metrics work without it, so this is best-effort.
@MainActor
@Observable
final class WiFiLocationAuth: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var status: CLAuthorizationStatus

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var needsRequest: Bool { status == .notDetermined }

    func request() { manager.requestWhenInUseAuthorization() }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let new = manager.authorizationStatus
        Task { @MainActor in self.status = new }
    }
}

// MARK: - Wi-Fi Signal

@MainActor
@Observable
final class WiFiSignalModel {
    private(set) var status: WiFiStatus?
    private var task: Task<Void, Never>?

    func refresh() { status = WiFiInfo().current() }

    /// Poll while the screen is visible — RSSI and rate drift constantly.
    func startPolling() {
        stopPolling()
        refresh()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.refresh()
            }
        }
    }
    func stopPolling() { task?.cancel(); task = nil }
}

struct WiFiSignalView: View {
    @State private var model = WiFiSignalModel()
    @State private var auth = WiFiLocationAuth()

    var body: some View {
        ToolScaffold {
            if let status = model.status {
                signalCard(status)
            } else {
                ContentUnavailableView("Wi-Fi выключен", systemImage: "wifi.slash",
                                       description: Text("Включите Wi-Fi, чтобы увидеть сигнал."))
                    .padding(.top, 40)
            }
        } content: {
            if let status = model.status {
                detailsCard(status)
                if status.ssid == nil, auth.status != .authorized {
                    locationHint
                }
            }
        } bottom: {
            RunButton(title: "Обновить", running: false) { model.refresh() }
        }
        .navigationTitle("Сигнал Wi-Fi")
        .onAppear { if auth.needsRequest { auth.request() }; model.startPolling() }
        .onDisappear { model.stopPolling() }
    }

    private func signalCard(_ status: WiFiStatus) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "wifi", variableValue: Double(status.quality.bars + 1) / 4)
                .font(.system(size: 44))
                .foregroundStyle(color(status.quality))
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(status.rssi) dBm · \(status.quality.label)").font(.title3.weight(.bold))
                Text(status.ssid ?? "Сеть — нужен доступ к геопозиции")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18).card()
    }

    private func detailsCard(_ status: WiFiStatus) -> some View {
        VStack(spacing: 0) {
            InfoRow(label: "Сеть", value: status.ssid ?? "—")
            Divider().padding(.leading, 14)
            InfoRow(label: "Канал", value: "\(status.channel) · \(status.band.label) · \(status.width.label)")
            Divider().padding(.leading, 14)
            InfoRow(label: "Скорость", value: "\(Int(status.txRateMbps)) Мбит/с")
            Divider().padding(.leading, 14)
            InfoRow(label: "Сигнал / шум", value: "\(status.rssi) / \(status.noise) dBm (SNR \(status.snr))")
            Divider().padding(.leading, 14)
            InfoRow(label: "Стандарт", value: status.phyMode.label)
            if let bssid = status.bssid {
                Divider().padding(.leading, 14)
                InfoRow(label: "BSSID", value: bssid, mono: true)
            }
            Divider().padding(.leading, 14)
            InfoRow(label: "Интерфейс", value: status.interfaceName, mono: true)
        }
        .card()
    }

    private var locationHint: some View {
        Button { auth.request() } label: {
            Label("Разрешить геопозицию, чтобы видеть имя сети", systemImage: "location")
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .buttonStyle(.plain)
        .card()
    }

    private func color(_ quality: WiFiQuality) -> Color {
        switch quality {
        case .excellent: .green
        case .good: .mint
        case .fair: .orange
        case .poor: .red
        }
    }
}

// MARK: - Wi-Fi Analysis (scan)

@MainActor
@Observable
final class WiFiAnalysisModel {
    private(set) var networks: [WiFiNetwork] = []
    private(set) var isScanning = false
    private(set) var errorMessage: String?

    func scan() {
        isScanning = true; errorMessage = nil
        Task { [weak self] in
            do {
                let found = try await WiFiInfo().scan()
                self?.networks = found
            } catch {
                self?.errorMessage = error.localizedDescription
            }
            self?.isScanning = false
        }
    }

    /// Channel occupancy per band, for the summary.
    var byBand: [(band: WiFiBand, networks: [WiFiNetwork])] {
        let order: [WiFiBand] = [.ghz24, .ghz5, .ghz6]
        return order.compactMap { band in
            let list = networks.filter { $0.band == band }
            return list.isEmpty ? nil : (band, list)
        }
    }
}

struct WiFiAnalysisView: View {
    @State private var model = WiFiAnalysisModel()
    @State private var auth = WiFiLocationAuth()

    var body: some View {
        ToolScaffold {
            if let error = model.errorMessage {
                ErrorCard(message: error) { model.scan() }
            } else if model.networks.isEmpty, model.isScanning {
                ProgressView("Сканирование…").padding(.top, 40)
            } else if model.networks.isEmpty {
                ToolIdleHint(icon: "wifi", title: "Анализ Wi-Fi",
                             message: "Просканируем эфир: соседние сети, их каналы, диапазоны и уровень сигнала. Видно, какие каналы перегружены. Нужен доступ к геопозиции.")
            }
        } content: {
            ForEach(model.byBand, id: \.band) { group in
                bandCard(group.band, group.networks)
            }
        } bottom: {
            RunButton(title: "Сканировать", running: model.isScanning) { model.scan() }
        }
        .navigationTitle("Wi-Fi анализ")
        .onAppear { if auth.needsRequest { auth.request() } }
    }

    private func bandCard(_ band: WiFiBand, _ networks: [WiFiNetwork]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: "\(band.label) · \(networks.count) сетей")
            VStack(spacing: 0) {
                ForEach(Array(networks.enumerated()), id: \.element.id) { idx, network in
                    HStack(spacing: 11) {
                        Image(systemName: network.isSecure ? "lock.fill" : "lock.open")
                            .font(.caption).foregroundStyle(.secondary).frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(network.ssid?.isEmpty == false ? network.ssid! : "(скрытая)")
                                if network.isCurrent {
                                    Text("текущая").font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tint)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(.tint.opacity(0.15), in: Capsule())
                                }
                            }
                            Text("канал \(network.channel) · \(network.width.label)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(network.rssi) dBm")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(color(network.quality))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    if idx < networks.count - 1 { Divider().padding(.leading, 40) }
                }
            }
            .card()
        }
    }

    private func color(_ quality: WiFiQuality) -> Color {
        switch quality {
        case .excellent: .green
        case .good: .mint
        case .fair: .orange
        case .poor: .red
        }
    }
}
#endif
