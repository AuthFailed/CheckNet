import SwiftUI
import NetworkKit

/// Разбор существующего профиля роутинга Happ: вставить `happ://routing/add/…`
/// (или `…/onadd/…`) → подробный читаемый разбор — DNS, geo-источники,
/// DNS-хосты и все правила Direct/Proxy/Block по категориям. Полноценный
/// визуальный конструктор — отдельная дизайн-задача (issue #76).
struct HappRoutingView: View {
    @State private var input = ""
    @State private var profile: HappRoutingProfile?
    @State private var error: String?

    var body: some View {
        Form {
            inputSection
            if let profile {
                summarySection(profile)
                basicsSection(profile)
                dnsSection(profile)
                geoSection(profile)
                ruleSection("DIRECT", sites: profile.directSites, ips: profile.directIP, tint: .green)
                ruleSection("PROXY", sites: profile.proxySites, ips: profile.proxyIP, tint: .blue)
                ruleSection("BLOCK", sites: profile.blockSites, ips: profile.blockIP, tint: .red)
            }
        }
        .navigationTitle("Роутинг Happ")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            InfoButton(title: VPNTool.happRouting.title,
                       systemImage: VPNTool.happRouting.systemImage,
                       message: VPNTool.happRouting.info)
        }
    }

    // MARK: - Input

    private var inputSection: some View {
        Section {
            TextField("happ://routing/add/…", text: $input, axis: .vertical)
                .lineLimit(2...5)
                .font(.callout.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            HStack {
                Button {
                    if let s = clipboardString() { input = s }
                } label: { Label("Вставить", systemImage: "doc.on.clipboard") }
                Spacer()
                Button { parse() } label: {
                    Label("Разобрать", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } footer: {
            if let error {
                Label(LocalizedStringKey(error), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Result

    @ViewBuilder
    private func summarySection(_ p: HappRoutingProfile) -> some View {
        Section {
            if !p.name.isEmpty {
                HStack {
                    Image(systemName: "arrow.triangle.branch").foregroundStyle(.tint)
                    Text(p.name).font(.headline)
                }
            }
            HStack(spacing: 8) {
                countPill("Direct", p.directSites.count + p.directIP.count, .green)
                countPill("Proxy", p.proxySites.count + p.proxyIP.count, .blue)
                countPill("Block", p.blockSites.count + p.blockIP.count, .red)
                if !p.dnsHosts.isEmpty { countPill("DNS-хосты", p.dnsHosts.count, .orange) }
            }
            .font(.caption)
            if let date = p.lastUpdatedDate {
                InfoRow(label: "Обновлён", value: date.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private func countPill(_ label: LocalizedStringKey, _ n: Int, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text("\(n)").bold().foregroundStyle(tint)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func basicsSection(_ p: HappRoutingProfile) -> some View {
        Section("Основное") {
            InfoRow(label: "Глобальный прокси", value: p.globalProxy ? "да" : "нет")
            if !p.routeOrder.isEmpty { InfoRow(label: "Порядок правил", value: p.routeOrder) }
            InfoRow(label: "Domain strategy", value: p.domainStrategy)
            InfoRow(label: "FakeDNS", value: p.fakeDNS ? "вкл" : "выкл")
            if p.useChunkFiles { InfoRow(label: "Chunk files", value: "вкл") }
        }
    }

    @ViewBuilder
    private func dnsSection(_ p: HappRoutingProfile) -> some View {
        Section("DNS") {
            dnsRow(label: "Remote", server: p.remoteDNS, type: p.remoteDNSType,
                   domain: p.remoteDNSDomain, ip: p.remoteDNSIP)
            dnsRow(label: "Domestic", server: p.domesticDNS, type: p.domesticDNSType,
                   domain: p.domesticDNSDomain, ip: p.domesticDNSIP)
            if !p.dnsHosts.isEmpty {
                DisclosureGroup("DNS-хосты · \(p.dnsHosts.count)") {
                    ForEach(p.dnsHosts.sorted(by: { $0.key < $1.key }), id: \.key) { host, ip in
                        InfoRow(label: host, value: ip, mono: true)
                    }
                }
            }
        }
    }

    private func dnsRow(label: String, server: String, type: String, domain: String, ip: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(LocalizedStringKey(label)).foregroundStyle(.secondary)
                Spacer()
                Text(type).font(.caption.weight(.medium))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            let detail = [server, domain, ip].filter { !$0.isEmpty }.joined(separator: " · ")
            if !detail.isEmpty {
                Text(detail).font(.footnote.monospaced()).foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func geoSection(_ p: HappRoutingProfile) -> some View {
        if !p.geoSiteURL.isEmpty || !p.geoIPURL.isEmpty {
            Section("Geo-источники") {
                if !p.geoSiteURL.isEmpty { geoRow("geosite", p.geoSiteURL) }
                if !p.geoIPURL.isEmpty { geoRow("geoip", p.geoIPURL) }
            }
        }
    }

    private func geoRow(_ label: String, _ url: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(url).font(.footnote.monospaced()).textSelection(.enabled)
                .lineLimit(3).truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func ruleSection(_ title: String, sites: [String], ips: [String], tint: Color) -> some View {
        let entries = (sites + ips).map(HappRuleEntry.classify)
        if !entries.isEmpty {
            Section {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    ruleRow(entry)
                }
            } header: {
                Label("\(title) · \(entries.count)", systemImage: "circle.fill")
                    .foregroundStyle(tint)
            }
        }
    }

    private func ruleRow(_ entry: HappRuleEntry) -> some View {
        HStack(spacing: 10) {
            Text(tag(for: entry).0)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tag(for: entry).1)
                .frame(width: 58, alignment: .leading)
            Text(entry.value).font(.callout.monospaced()).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }

    private func tag(for entry: HappRuleEntry) -> (String, Color) {
        switch entry {
        case .geositeTag: ("geosite", .purple)
        case .geoipTag: ("geoip", .teal)
        case .ipCIDR: ("IP", .orange)
        case .domain: ("домен", .blue)
        case .raw: ("правило", .gray)
        }
    }

    // MARK: - Parsing

    private func parse() {
        error = nil
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            profile = try HappRoutingLink.decode(trimmed)
        } catch {
            profile = nil
            self.error = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        switch error as? HappRoutingLink.DecodeError {
        case .notARoutingLink: "Это не ссылка happ://routing/add/…"
        case .invalidBase64: "Не удалось раскодировать base64"
        case .notAnObject: "Внутри не JSON-профиль роутинга"
        case nil: "Не удалось разобрать ссылку"
        }
    }

    private func clipboardString() -> String? {
        #if os(iOS)
        return UIPasteboard.general.string
        #elseif os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #else
        return nil
        #endif
    }
}
