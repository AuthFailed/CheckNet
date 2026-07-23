import SwiftUI
import MapKit
import NetworkKit

struct IPLocationView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var query = ""
    @State private var run = ToolRunModel<IPGeoLookup>()

    private func start() {
        guard !run.isRunning else { return }
        let q = query.trimmingCharacters(in: .whitespaces)
        run.start { try await IPGeolocation().lookup(query: q) }
    }

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $query, placeholder: "IP или домен (пусто — ваш IP)",
                         icon: "mappin.and.ellipse", disabled: run.isRunning,
                         savedHostTool: .ipLocation) { start() }
            if let error = run.errorMessage {
                ErrorCard(message: error) { start() }
            } else if let lookup = run.value {
                headerCard(lookup.consensus)
            } else if run.isRunning {
                ProgressView().padding(.top, 40)
            }
        } content: {
            if run.errorMessage == nil, let lookup = run.value {
                mapCard(lookup.consensus)
                detailsCard(lookup.consensus)
                if hasRiskFlags(lookup.consensus) { riskCard(lookup.consensus) }
                providerTable(lookup.providers)
                linksCard(lookup.consensus, ip: lookup.ip)
            } else if run.value == nil, !run.isRunning {
                ToolIdleHint(
                    icon: "mappin.and.ellipse",
                    title: "Где находится адрес",
                    message: "Опросим сразу несколько сервисов геолокации и покажем согласованный результат — страну, город, сеть (ASN и оператора) — плюс ответ каждого сервиса отдельно. Пустое поле — ваш публичный IP.",
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

    private func headerCard(_ c: IPGeoConsensus) -> some View {
        HStack(spacing: 14) {
            if let flag = c.flagEmoji {
                Text(flag).font(.system(size: 40))
            } else {
                Image(systemName: "globe").font(.largeTitle).foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(c.country ?? "Неизвестно").font(.title3.weight(.bold))
                let place = [c.city, c.region].compactMap { $0 }.joined(separator: ", ")
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
    private func mapCard(_ c: IPGeoConsensus) -> some View {
        if let lat = c.latitude, let lon = c.longitude {
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            let region = MKCoordinateRegion(center: coord,
                                            latitudinalMeters: 300_000, longitudinalMeters: 300_000)
            Map(initialPosition: .region(region), interactionModes: []) {
                Marker(c.city ?? c.country ?? c.ip, coordinate: coord)
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: Palette.hairlineWidth))
            .accessibilityLabel("Карта: \(c.city ?? c.country ?? "местоположение")")
        }
    }

    // MARK: Consensus details

    private func detailsCard(_ c: IPGeoConsensus) -> some View {
        VStack(spacing: 0) {
            InfoRow(label: "IP", value: c.ip, mono: true)
            if let asn = c.asn {
                Divider().padding(.leading, 14)
                InfoRow(label: "Сеть (ASN)", value: [asn, c.asnOrg].compactMap { $0 }.joined(separator: " · "))
            }
            if let tz = c.timezone {
                Divider().padding(.leading, 14)
                InfoRow(label: "Часовой пояс", value: tz)
            }
            if let lat = c.latitude, let lon = c.longitude {
                Divider().padding(.leading, 14)
                InfoRow(label: "Координаты", value: String(format: "%.4f, %.4f", lat, lon), mono: true)
            }
            Divider().padding(.leading, 14)
            InfoRow(label: "Источников согласны", value: "\(c.sourceCount)")
        }
        .card()
    }

    // MARK: Per-provider comparison

    private func providerTable(_ providers: [IPGeoResult]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: "По сервисам")
            VStack(spacing: 0) {
                ForEach(Array(providers.enumerated()), id: \.element.id) { idx, p in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(p.source)
                            .font(.caption.weight(.semibold))
                            .frame(width: 96, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(p.flagEmoji ?? "") \([p.country, p.city].compactMap { $0 }.joined(separator: ", "))"
                                .trimmingCharacters(in: .whitespaces))
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(p.asn.map { [$0, p.asnOrg].compactMap { $0 }.joined(separator: " · ") } ?? "ASN —")
                                .font(.caption2.monospaced()).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    if idx < providers.count - 1 { Divider().padding(.leading, 14) }
                }
            }
            .card()
        }
    }

    // MARK: Risk flags

    private func hasRiskFlags(_ c: IPGeoConsensus) -> Bool {
        [c.isHosting, c.isVPN, c.isProxy, c.isTor].contains(true)
    }

    private func riskCard(_ c: IPGeoConsensus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: "Тип адреса")
            HStack(spacing: 8) {
                if c.isHosting == true { badge("Дата-центр", "server.rack", .orange) }
                if c.isVPN == true { badge("VPN", "lock.shield", .blue) }
                if c.isProxy == true { badge("Прокси", "arrow.triangle.branch", .blue) }
                if c.isTor == true { badge("Tor", "eye.slash", .purple) }
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

    private func linksCard(_ c: IPGeoConsensus, ip: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: "Внешние ресурсы")
            VStack(spacing: 0) {
                let links = externalLinks(c, ip: ip)
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

    private func externalLinks(_ c: IPGeoConsensus, ip: String) -> [ExternalLink] {
        var out: [ExternalLink] = []
        if let n = c.asNumber {
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
        if let u = URL(string: "https://bgp.tools/prefix/\(ip)") {
            out.append(.init(title: "bgp.tools", subtitle: "префикс, покрывающий \(ip)", icon: "square.stack.3d.up", url: u))
        }
        return out
    }
}
