import SwiftUI
import NetworkKit

/// "Current Wi-Fi network" — the network the device is on right now.
///
/// The data set differs by platform, and that is the point of the screen:
/// - **iOS/iPadOS**: only the identity iOS exposes to apps — SSID, BSSID,
///   security (`CurrentNetwork` → `WiFiIdentity`). RF metrics (RSSI, channel)
///   are not available to apps on iOS, so the screen says so plainly.
/// - **macOS**: the full link via CoreWLAN (`WiFiInfo` → `WiFiStatus`): signal,
///   channel, band, rate, PHY, plus a live poll. RF reads without Location; the
///   SSID needs it, so the no-access state keeps the metrics and only withholds
///   the name.
@MainActor
@Observable
final class CurrentWiFiModel {
    enum Phase: Equatable { case idle, running, offline, noAccess, success }
    private(set) var phase: Phase = .idle

    #if os(iOS)
    private(set) var identity: WiFiIdentity?
    #else
    private(set) var status: WiFiStatus?
    var live = true {
        didSet { live ? startPolling() : stopPolling() }
    }
    private var pollTask: Task<Void, Never>?
    #endif

    func refresh() async {
        phase = .running
        #if os(iOS)
        switch await CurrentNetwork.current() {
        case .connected(let info): identity = info; phase = .success
        case .restricted:          identity = nil;  phase = .noAccess
        case .unavailable:         identity = nil;  phase = .offline
        }
        #else
        if let s = WiFiInfo().current() {
            status = s
            phase = s.ssid == nil ? .noAccess : .success
            if live { startPolling() }
        } else {
            status = nil
            phase = .offline
            stopPolling()
        }
        #endif
    }

    #if os(macOS)
    /// RF metrics drift constantly; re-read every 2 s while the screen is up.
    /// Identity fields don't change, so this only refreshes `status` in place
    /// rather than driving the phase back through `.running`.
    func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.live else { break }
                if let s = WiFiInfo().current() {
                    self.status = s
                    if self.phase == .offline { self.phase = s.ssid == nil ? .noAccess : .success }
                } else {
                    self.status = nil
                    self.phase = .offline
                }
            }
        }
    }
    func stopPolling() { pollTask?.cancel(); pollTask = nil }
    #endif
}

struct CurrentWiFiView: View {
    @State private var model = CurrentWiFiModel()
    #if os(macOS)
    @State private var auth = WiFiLocationAuth()
    #endif

    var body: some View {
        ToolScaffold {
            leadingColumn
        } content: {
            detailCards
        } bottom: {
            bottomBar
        }
        .navigationTitle("Current Wi-Fi network")
        .toolTitleDisplayMode()
        .task { await model.refresh() }
        #if os(macOS)
        .onAppear { if auth.needsRequest { auth.request() } }
        .onDisappear { model.stopPolling() }
        #endif
    }

    // MARK: Primary column

    @ViewBuilder private var leadingColumn: some View {
        switch model.phase {
        case .idle:
            ToolIdleHint(
                icon: "wifi",
                title: "Current Wi-Fi network",
                message: "We'll show the network the device is connected to right now: name, access point BSSID and security type. Neighboring networks aren't scanned."
            )
        case .running:
            VStack(spacing: 12) {
                ProgressView()
                Text("Detecting network…").font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        case .offline:
            ContentUnavailableView {
                Label("You're not connected to Wi-Fi", systemImage: "wifi.slash")
            } description: {
                Text("Connect to a Wi-Fi network and tap \"Refresh\". The tool reads only the current connection.")
            }
            .padding(.top, 24)
        case .noAccess:
            #if os(iOS)
            accessCard
            #else
            heroCard
            #endif
        case .success:
            heroCard
        }
    }

    // MARK: Detail cards (result grid)

    @ViewBuilder private var detailCards: some View {
        #if os(iOS)
        if model.phase == .success, let info = model.identity {
            iosConnectionCard(info)
            iosLimitationNote
        }
        #else
        if let status = model.status, model.phase == .success || model.phase == .noAccess {
            macConnectionCard(status)
            if model.phase == .noAccess { accessCard }
        }
        #endif
    }

    // MARK: Bottom

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: 12) {
            RunButton(title: "Refresh", running: model.phase == .running) {
                Task { await model.refresh() }
            }
            #if os(macOS)
            if model.status != nil {
                Toggle(isOn: Binding(get: { model.live }, set: { model.live = $0 })) {
                    HStack {
                        Text("Live update")
                        Spacer()
                        Text("every 2 s").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padding(.horizontal, 4)
            }
            #endif
        }
    }

    // MARK: Hero

    @ViewBuilder private var heroCard: some View {
        HStack(spacing: 16) {
            #if os(macOS)
            if let status = model.status {
                Image(systemName: "wifi", variableValue: Double(status.quality.bars + 1) / 4)
                    .font(.system(.largeTitle))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(qualityColor(status.quality))
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(status.rssi) dBm · ")
                        .font(.title3.weight(.bold))
                    + Text(LocalizedStringKey(status.quality.label)).font(.title3.weight(.bold))
                    Text(status.ssid ?? "Network name — location access required")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            #else
            if let info = model.identity {
                Image(systemName: "wifi")
                    .font(.system(.largeTitle))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(info.ssid).font(.title3.weight(.bold))
                    Text("Connected · Wi-Fi").font(.caption2).foregroundStyle(.secondary)
                }
            }
            #endif
            Spacer(minLength: 0)
        }
        .padding(18)
        .card()
        .accessibilityElement(children: .combine)
    }

    // MARK: iOS cards

    #if os(iOS)
    private func iosConnectionCard(_ info: WiFiIdentity) -> some View {
        VStack(spacing: 0) {
            InfoRow(label: "Network", value: info.ssid)
            if let bssid = info.bssidDisplay {
                divider
                InfoRow(label: "BSSID", value: bssid, mono: true)
            }
            divider
            securityRow(label: info.securityLabel, isSecure: info.isSecure)
        }
        .card()
    }

    private var iosLimitationNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("iOS doesn't report signal level and channel to apps — they're available in the Mac version.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
    #endif

    // MARK: macOS card

    #if os(macOS)
    private func macConnectionCard(_ status: WiFiStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: "Connection")
            VStack(spacing: 0) {
                InfoRow(label: "Network",
                        value: status.ssid ?? "— access required",
                        valueColor: status.ssid == nil ? .secondary : .primary)
                divider
                InfoRow(label: "Channel", value: "\(status.channel) · \(status.band.label) · \(status.width.label)")
                divider
                InfoRow(label: "Speed", value: "\(Int(status.txRateMbps)) Mbps")
                divider
                InfoRow(label: "Signal / noise", value: "\(status.rssi) / \(status.noise) dBm (SNR \(status.snr))")
                divider
                InfoRow(label: "Standard", value: status.phyMode.label)
                if let bssid = status.bssid {
                    divider
                    InfoRow(label: "BSSID", value: bssid, mono: true)
                }
                divider
                InfoRow(label: "Interface", value: status.interfaceName, mono: true)
            }
            .card()
        }
    }
    #endif

    // MARK: Access card (permission)

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Location access required", systemImage: "location")
                .font(.subheadline.weight(.semibold))
            Text(accessBody)
                .font(.callout)
            Text("Location is only needed to read the network name — coordinates are not stored or sent.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Grant access") {
                #if os(macOS)
                auth.request()
                #endif
                Task { await model.refresh() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var accessBody: LocalizedStringKey {
        #if os(macOS)
        "macOS reveals the network name (SSID) only with location access. Radio metrics are readable without it."
        #else
        "iOS only gives the network name (SSID) to apps with location access. Grant access to see which network you're connected to."
        #endif
    }

    // MARK: Bits

    private var divider: some View { Divider().padding(.leading, 14) }

    /// A key/value row where the value carries a lock icon + colour, which the
    /// plain `InfoRow` can't express.
    private func securityRow(label: String, isSecure: Bool) -> some View {
        HStack(alignment: .top) {
            Text("Security").foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Label {
                Text(LocalizedStringKey(label))
            } icon: {
                Image(systemName: isSecure ? "lock.fill" : "lock.open")
            }
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isSecure ? AnyShapeStyle(.primary) : AnyShapeStyle(.orange))
            .multilineTextAlignment(.trailing)
        }
        .font(.callout)
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func qualityColor(_ q: WiFiQuality) -> Color {
        switch q {
        case .excellent: .green
        case .good: .mint
        case .fair: .orange
        case .poor: .red
        }
    }
}
