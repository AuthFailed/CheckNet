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
                ProgressView("Scanning…").padding(.top, 40)
            } else if model.networks.isEmpty {
                ToolIdleHint(icon: "wifi", title: "Wi-Fi analysis",
                             message: "We scan the air: neighboring networks, their channels, bands and signal level. You see which channels are congested. Location access is required.")
            }
        } content: {
            ForEach(model.byBand, id: \.band) { group in
                bandCard(group.band, group.networks)
            }
        } bottom: {
            RunButton(title: "Scan", running: model.isScanning) { model.scan() }
        }
        .navigationTitle("Wi-Fi analysis")
        .onAppear { if auth.needsRequest { auth.request() } }
    }

    private func bandCard(_ band: WiFiBand, _ networks: [WiFiNetwork]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: "\(band.label) · \(networks.count) networks")
            VStack(spacing: 0) {
                ForEach(Array(networks.enumerated()), id: \.element.id) { idx, network in
                    HStack(spacing: 11) {
                        Image(systemName: network.isSecure ? "lock.fill" : "lock.open")
                            .font(.caption).foregroundStyle(.secondary).frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(network.ssid?.isEmpty == false ? network.ssid! : "(hidden)")
                                if network.isCurrent {
                                    Text("current").font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tint)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(.tint.opacity(0.15), in: Capsule())
                                }
                            }
                            Text("channel \(network.channel) · \(network.width.label)")
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
