import SwiftUI
import MapKit
import NetworkKit

struct IPLocationView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var query = ""
    @State private var run = ToolRunModel<IPGeoResult>()

    private func start() {
        guard !run.isRunning else { return }
        let q = query.trimmingCharacters(in: .whitespaces)
        run.start { try await IPGeolocation().locate(query: q) }
    }

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $query, placeholder: "IP или домен (пусто — ваш IP)",
                         icon: "mappin.and.ellipse", disabled: run.isRunning,
                         savedHostTool: .ipLocation) { start() }
            if let error = run.errorMessage {
                ErrorCard(message: error) { start() }
            } else if let result = run.value {
                headerCard(result)
            } else if run.isRunning {
                ProgressView().padding(.top, 40)
            }
        } content: {
            if run.errorMessage == nil, let result = run.value {
                mapCard(result)
                detailsCard(result)
                if hasRiskFlags(result) { riskCard(result) }
                linksCard(result)
            } else if run.value == nil, !run.isRunning {
                ToolIdleHint(
                    icon: "mappin.and.ellipse",
                    title: "Где находится адрес",
                    message: "Определим страну, город, сеть (ASN и оператора) для IP или домена. Оставьте поле пустым, чтобы узнать свой публичный IP. Запрос уходит к сервису геолокации.",
                    example: "1.1.1.1",
                    current: query
                ) { query = "1.1.1.1" }
            }
        } bottom: {
            RunButton(title: "Определить", running: run.isRunning) { start() }
        }
        .animation(.snappy, value: run.value)
        .haptic(.success, trigger: run.isRunning) { !$0 && run.errorMessage == nil }
        .haptic(.failure, trigger: run.isRunning) { !$0 && run.errorMessage != nil }
        .navigationTitle("Геолокация IP")
        .toolTitleDisplayMode()
        .onAppear {
            if let presetHost { query = presetHost }
            if autostart { start() }
        }
    }

    // MARK: Header

    private func headerCard(_ r: IPGeoResult) -> some View {
        HStack(spacing: 14) {
            if let flag = r.flagEmoji {
                Text(flag).font(.system(size: 40))
            } else {
                Image(systemName: "globe").font(.largeTitle).foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(r.country ?? "Неизвестно").font(.title3.weight(.bold))
                let place = [r.city, r.region].compactMap { $0 }.joined(separator: ", ")
                if !place.isEmpty {
                    Text(place).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .card()
    }

    // MARK: Map

    @ViewBuilder
    private func mapCard(_ r: IPGeoResult) -> some View {
        if let lat = r.latitude, let lon = r.longitude {
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            let region = MKCoordinateRegion(center: coord,
                                            latitudinalMeters: 300_000, longitudinalMeters: 300_000)
            Map(initialPosition: .region(region), interactionModes: []) {
                Marker(r.city ?? r.country ?? r.ip, coordinate: coord)
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: Palette.hairlineWidth))
            .accessibilityLabel("Карта: \(r.city ?? r.country ?? "местоположение")")
        }
    }

    // MARK: Details

    private func detailsCard(_ r: IPGeoResult) -> some View {
        VStack(spacing: 0) {
            InfoRow(label: "IP", value: r.ip, mono: true)
            if let asn = r.asn {
                Divider().padding(.leading, 14)
                InfoRow(label: "Сеть (ASN)", value: "\(asn) · \(r.asnOrg ?? "")")
            }
            if let isp = r.isp, isp != r.asnOrg {
                Divider().padding(.leading, 14)
                InfoRow(label: "Оператор", value: isp)
            }
            if let tz = r.timezone {
                Divider().padding(.leading, 14)
                InfoRow(label: "Часовой пояс", value: tz)
            }
            if let lat = r.latitude, let lon = r.longitude {
                Divider().padding(.leading, 14)
                InfoRow(label: "Координаты",
                        value: String(format: "%.4f, %.4f", lat, lon), mono: true)
            }
            Divider().padding(.leading, 14)
            InfoRow(label: "Источник", value: r.source)
        }
        .card()
    }

    // MARK: Risk flags

    private func hasRiskFlags(_ r: IPGeoResult) -> Bool {
        [r.isHosting, r.isVPN, r.isProxy, r.isTor].contains(true)
    }

    private func riskCard(_ r: IPGeoResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: "Тип адреса")
            HStack(spacing: 8) {
                if r.isHosting == true { badge("Дата-центр", "server.rack", .orange) }
                if r.isVPN == true { badge("VPN", "lock.shield", .blue) }
                if r.isProxy == true { badge("Прокси", "arrow.triangle.branch", .blue) }
                if r.isTor == true { badge("Tor", "eye.slash", .purple) }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func badge(_ text: LocalizedStringKey, _ icon: String, _ color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
    }

    // MARK: External links

    private func linksCard(_ r: IPGeoResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: "Внешние ресурсы")
            VStack(spacing: 0) {
                let links = externalLinks(r)
                ForEach(Array(links.enumerated()), id: \.offset) { idx, link in
                    Link(destination: link.url) {
                        HStack {
                            Image(systemName: link.icon).foregroundStyle(.tint).frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(link.title).foregroundStyle(.primary)
                                Text(link.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                    }
                    if idx < links.count - 1 { Divider().padding(.leading, 48) }
                }
            }
            .card()
            Text("Открываются в браузере — детали о сети, префиксе и точках обмена трафиком.")
                .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
    }

    private struct ExternalLink { let title: String; let subtitle: String; let icon: String; let url: URL }

    private func externalLinks(_ r: IPGeoResult) -> [ExternalLink] {
        var out: [ExternalLink] = []
        if let n = r.asNumber {
            if let u = URL(string: "https://bgp.tools/as/\(n)") {
                out.append(.init(title: "bgp.tools", subtitle: "AS\(n) — соседи, префиксы", icon: "point.3.connected.trianglepath.dotted", url: u))
            }
            if let u = URL(string: "https://bgp.he.net/AS\(n)") {
                out.append(.init(title: "Hurricane Electric", subtitle: "AS\(n) — BGP-обзор", icon: "network", url: u))
            }
            if let u = URL(string: "https://www.peeringdb.com/asn/\(n)") {
                out.append(.init(title: "PeeringDB", subtitle: "AS\(n) — точки обмена и объекты", icon: "building.2", url: u))
            }
        }
        if let u = URL(string: "https://bgp.tools/prefix/\(r.ip)") {
            out.append(.init(title: "bgp.tools", subtitle: "префикс, покрывающий \(r.ip)", icon: "square.stack.3d.up", url: u))
        }
        return out
    }
}
