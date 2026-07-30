import SwiftUI
import NetworkKit

/// Subscription parsing → server list (issue #72). Paste a URL / raw content /
/// `happ://` / `incy://`, pick a User-Agent (Auto by default), and get nodes
/// with a country flag, remark, badges and ping. Search by any parameter,
/// filter by protocol, and check reachability (TCP) and SNI blocking per server
/// or in bulk.
///
/// Ping here is the TCP reachability of the server itself. The "through proxy to
/// gstatic" check needs a proxy client and lives in the "Xray reachability" tool (#71).
/// A dimension the server list can be filtered by. Only the ones that actually
/// vary in the parsed subscription are shown.
enum ServerFacet: String, CaseIterable, Identifiable {
    case proto, security, network, port, fingerprint, sni, country, flow
    var id: String { rawValue }
    var title: String {
        switch self {
        case .proto: "Протокол"
        case .security: "Безопасность"
        case .network: "Транспорт"
        case .port: "Порт"
        case .fingerprint: "Fingerprint"
        case .sni: "SNI"
        case .country: "Страна"
        case .flow: "Flow"
        }
    }
    var icon: String {
        switch self {
        case .proto: "shield.lefthalf.filled"
        case .security: "lock"
        case .network: "network"
        case .port: "number"
        case .fingerprint: "hand.point.up.braille"
        case .sni: "globe"
        case .country: "flag"
        case .flow: "arrow.left.arrow.right"
        }
    }
}

/// How the server list is ordered. `original` keeps the order the subscription
/// delivered — the default, since providers order servers deliberately.
enum ServerSort: String, CaseIterable, Identifiable {
    case original, remark, ping, country, port
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: "По подписке"
        case .remark: "По имени"
        case .ping: "По пингу"
        case .country: "По стране"
        case .port: "По порту"
        }
    }
}

@MainActor
@Observable
final class SubscriptionModel {
    var input = ""
    var selectedUA = SubscriptionUserAgents.auto
    var search = ""
    var filters: [ServerFacet: String] = [:]
    var sort: ServerSort = .original

    var nodes: [ProxyNode] = []
    var format: SubscriptionFormat = .unknown
    var usedUA: String?
    var sourceNote: String?
    /// Full body as received — shown/copied on the detail screen.
    var rawContent = ""
    var error: String?
    var loading = false
    var pinging = false

    /// URL the subscription came from — used for the "share subscription" QR.
    var sourceURL: String?

    enum Ping: Equatable { case ms(Double), fail }
    var pings: [UUID: Ping] = [:]
    var snis: [UUID: CensorshipVerdict] = [:]
    var sniRunning = false
    /// Per-node in-flight state, so a finished check can be run again and the
    /// user still sees that it's working.
    var pingInFlight: Set<UUID> = []
    var sniInFlight: Set<UUID> = []

    /// Through-proxy ping (macOS, real Xray core): latency + HTTP status, or a
    /// reason it failed.
    enum ProxyPing: Equatable { case ms(Double, Int?), fail(String) }
    var proxyPings: [UUID: ProxyPing] = [:]
    var proxyInFlight: Set<UUID> = []

    /// Native TLS/Reality handshake reachability (all platforms): sends a real
    /// TLS 1.3 ClientHello with the node's dest SNI and reports the reaction +
    /// latency. Not a full tunnel — see the macOS "through proxy" check for that.
    struct Handshake: Equatable { let ms: Double; let reaction: JA3ProbeResult.Reaction }
    var handshakes: [UUID: Handshake] = [:]
    var handshakeInFlight: Set<UUID> = []

    func handshakePing(_ node: ProxyNode) async {
        handshakeInFlight.insert(node.id); defer { handshakeInFlight.remove(node.id) }
        let sni = node.sni.isEmpty ? node.host : node.sni
        let r = await JA3Probe().run(host: node.host, serverName: sni, profile: .chrome, port: UInt16(node.port))
        handshakes[node.id] = Handshake(ms: r.elapsedMillis, reaction: r.reaction)
    }

    #if os(macOS)
    func proxyPing(_ node: ProxyNode, coreBinary: URL) async {
        proxyInFlight.insert(node.id); defer { proxyInFlight.remove(node.id) }
        do {
            let r = try await XrayProxyRunner.probe(node: node, coreBinary: coreBinary)
            proxyPings[node.id] = .ms(r.latencyMillis, r.httpStatus)
        } catch {
            proxyPings[node.id] = .fail((error as? XrayProxyRunner.RunError)?.message ?? "ошибка прокси")
        }
    }
    #endif

    /// A node's value for a facet, or nil if it doesn't have one.
    func facetValue(_ f: ServerFacet, _ n: ProxyNode) -> String? {
        switch f {
        case .proto: n.proto.rawValue
        case .security: n.isReality ? "reality" : (n.security.isEmpty ? nil : n.security.lowercased())
        case .network: n.network.isEmpty ? nil : n.network.lowercased()
        case .port: String(n.port)
        case .fingerprint: fingerprint(n)
        case .sni: n.sni.isEmpty ? nil : n.sni
        case .country: countryFlag(n)
        case .flow: n.flow.isEmpty ? nil : n.flow
        }
    }

    /// Distinct values present for a facet, nicely ordered.
    func facetValues(_ f: ServerFacet) -> [String] {
        var set = Set<String>()
        for n in nodes { if let v = facetValue(f, n) { set.insert(v) } }
        return set.sorted { a, b in
            if f == .port, let x = Int(a), let y = Int(b) { return x < y }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }

    /// Facets worth offering: either several distinct values, or a single value
    /// that only some nodes have (so picking it still narrows the list — e.g. a
    /// couple of 🇵🇱 servers among many unlabelled "proxy" ones).
    var availableFacets: [ServerFacet] {
        ServerFacet.allCases.filter { f in
            let values = facetValues(f)
            if values.count >= 2 { return true }
            if values.count == 1 { return nodes.contains { facetValue(f, $0) == nil } }
            return false
        }
    }

    private func fingerprint(_ n: ProxyNode) -> String? {
        let e = Dictionary(n.extras.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        return e["fp"]
            ?? e["streamsettings.realitysettings.fingerprint"]
            ?? e["streamsettings.tlssettings.fingerprint"]
    }

    private func countryFlag(_ n: ProxyNode) -> String? {
        let flag = CountryFlag.split(n.name).flag
        return flag == "🌐" ? nil : flag
    }

    var filtered: [ProxyNode] {
        var r = nodes.filter { node in
            (search.isEmpty || matches(node, search))
            && filters.allSatisfy { facet, value in facetValue(facet, node) == value }
        }
        switch sort {
        case .original: break     // keep the subscription's own order
        case .remark: r.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .ping: r.sort { pingKey($0) < pingKey($1) }
        case .country: r.sort { (countryFlag($0) ?? "🌐").localizedCompare(countryFlag($1) ?? "🌐") == .orderedAscending }
        case .port: r.sort { $0.port < $1.port }
        }
        return r
    }

    /// Ping latency for sorting; un-pinged / failed sink to the bottom.
    private func pingKey(_ n: ProxyNode) -> Double {
        if case .ms(let ms) = pings[n.id] { return ms }
        return .greatestFiniteMagnitude
    }

    private func matches(_ n: ProxyNode, _ q: String) -> Bool {
        var parts = [n.name, n.host, String(n.port), n.proto.rawValue, n.security, n.sni, n.network, n.flow, n.raw]
        // Extras too — so "chrome", "pbk", "xhttp" or a shortId find their server.
        parts += n.extras.flatMap { [$0.key, $0.value] }
        return parts.joined(separator: "\n").range(of: q, options: .caseInsensitive) != nil
    }

    func resolveAndParse() async {
        error = nil; sourceNote = nil; loading = true
        defer { loading = false }
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("happ://crypt") {
            do { text = try HappDecrypt.decrypt(text); sourceNote = "Расшифровано из Happ-ссылки" }
            catch { self.error = "Не удалось расшифровать Happ-ссылку"; return }
        } else if text.hasPrefix("incy://crypt1/") {
            do { text = try IncyLink.decode(text).url; sourceNote = "Извлечено из Incy-ссылки" }
            catch { self.error = "Не удалось разобрать Incy-ссылку"; return }
        }

        if text.hasPrefix("http://") || text.hasPrefix("https://"),
           text.split(whereSeparator: { $0 == "\n" }).count == 1 {
            do {
                let out = try await SubscriptionFetcher.fetchAndParse(text, userAgent: selectedUA.header)
                apply(out.result)
                rawContent = out.content
                usedUA = out.userAgent
                sourceURL = text
                if out.result.nodes.isEmpty { error = "Сервер вернул неизвестный формат — попробуйте другой User-Agent" }
            } catch { self.error = "Не удалось загрузить подписку" }
        } else {
            apply(SubscriptionParser.parse(text)); rawContent = text; usedUA = nil; sourceURL = nil
        }

        // Auto-check SNI right after a successful parse — the operator almost
        // always needs to know whether dest is being cut before doing anything manual.
        if !nodes.isEmpty { await checkAllSNI() }
    }

    private func apply(_ r: SubscriptionParser.Result) {
        nodes = r.nodes; format = r.format
        pings = [:]; snis = [:]
    }

    /// Re-runnable: every call re-measures, so the user can retry a failed or
    /// stale result as often as they like.
    func ping(_ node: ProxyNode) async {
        pingInFlight.insert(node.id)
        defer { pingInFlight.remove(node.id) }
        let r = await PortScanner().check(host: node.host, port: node.port, timeout: 3)
        pings[node.id] = (r.isOpen ? .ms(r.latencyMillis ?? 0) : .fail)
    }

    func pingAll() async {
        pinging = true; defer { pinging = false }
        let targets = filtered
        await withTaskGroup(of: (UUID, Ping).self) { group in
            for node in targets {
                group.addTask {
                    let r = await PortScanner().check(host: node.host, port: node.port, timeout: 3)
                    return (node.id, r.isOpen ? .ms(r.latencyMillis ?? 0) : .fail)
                }
            }
            for await (id, res) in group { pings[id] = res }
        }
    }

    func checkSNI(_ node: ProxyNode) async {
        guard !node.sni.isEmpty else { return }
        sniInFlight.insert(node.id)
        defer { sniInFlight.remove(node.id) }
        let f = await CensorshipChecks().checkSNIBlocking(blockedDomain: node.sni)
        snis[node.id] = f.verdict
    }

    func checkAllSNI() async {
        sniRunning = true; defer { sniRunning = false }
        let bySNI = Dictionary(grouping: filtered.filter { !$0.sni.isEmpty }, by: \.sni)
        await withTaskGroup(of: (String, CensorshipVerdict).self) { group in
            for sni in bySNI.keys {
                group.addTask {
                    let f = await CensorshipChecks().checkSNIBlocking(blockedDomain: sni)
                    return (sni, f.verdict)
                }
            }
            for await (sni, v) in group {
                for node in bySNI[sni] ?? [] { snis[node.id] = v }
            }
        }
    }
}

struct SubscriptionView: View {
    @State private var model = SubscriptionModel()
    /// Row taps drive navigation explicitly: a NavigationLink nested next to the
    /// per-row action buttons swallows the tap in a List row.
    @State private var selected: ProxyNode?
    @Environment(SavedSubscriptionsStore.self) private var saved
    @State private var qr: QRPayload?

    var body: some View {
        List {
            inputSection
            if !model.nodes.isEmpty {
                searchSection
                actionsSection
                filterSection
                Section {
                    ForEach(model.filtered) { node in
                        ServerRow(node: node, model: model) { selected = node }
                    }
                } header: {
                    Text("Серверы · \(model.filtered.count)")
                } footer: {
                    Text(LocalizedStringKey(parseNote))
                }
            }
        }
        .navigationTitle("Серверы")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(item: $selected) { node in
            ServerDetailView(node: node, model: model)
        }
        .sheet(item: $qr) { QRShareSheet(payload: $0) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                InfoButton(title: VPNTool.subscription.title,
                           systemImage: VPNTool.subscription.systemImage,
                           message: VPNTool.subscription.info)
            }
        }
    }

    /// Search sits under the input block and only after a successful parse —
    /// above the input it had nothing to filter yet.
    private var searchSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Поиск: имя, хост, SNI, порт, fp…", text: $model.search)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                if !model.search.isEmpty {
                    Button { model.search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Очистить поиск")
                }
            }
        }
    }

    /// Saved subscriptions: pick one to substitute, or bookmark the current one.
    /// Same idea as the saved-hosts menu, but its own list (issue #72).
    @ViewBuilder private var savedMenu: some View {
        Menu {
            if !saved.items.isEmpty {
                Section("Сохранённые") {
                    ForEach(saved.items) { item in
                        Button { model.input = item.value } label: {
                            Label(item.name, systemImage: "list.bullet.rectangle")
                        }
                    }
                }
            }
            let current = model.input.trimmingCharacters(in: .whitespacesAndNewlines)
            if !current.isEmpty, !saved.contains(current) {
                Button { saved.add(name: "", value: current) } label: {
                    Label("Сохранить эту подписку", systemImage: "bookmark")
                }
            }
        } label: {
            // Icon-only: three labelled controls wrap the row on a phone.
            Image(systemName: "bookmark")
        }
        .accessibilityLabel("Сохранённые подписки")
        .disabled(saved.items.isEmpty && model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// Where the "how it was parsed" line lives now — one quiet caption instead
    /// of a card taking a whole screenful.
    private var parseNote: String {
        var parts = ["Формат: \(formatLabel(model.format))"]
        if let ua = model.usedUA {
            parts.append(model.selectedUA.header == nil ? "Авто выбрал UA: \(ua)" : "UA: \(ua)")
        }
        if let note = model.sourceNote { parts.append(note) }
        return parts.joined(separator: " · ")
    }

    /// Named actions — icon-only toolbar buttons said nothing about what they do.
    private var actionsSection: some View {
        Section {
            Button { Task { await model.pingAll() } } label: {
                HStack {
                    Label("Пинг всех серверов", systemImage: "bolt.horizontal.circle")
                    Spacer()
                    if model.pinging { ProgressView() }
                }
            }
            .disabled(model.pinging)

            Button { Task { await model.checkAllSNI() } } label: {
                HStack {
                    Label("Проверить SNI у всех", systemImage: "checkmark.shield")
                    Spacer()
                    if model.sniRunning { ProgressView() }
                }
            }
            .disabled(model.sniRunning)

            if let url = model.sourceURL {
                Button {
                    qr = QRPayload(title: "Подписка", text: url)
                } label: { Label("Поделиться подпиской (QR)", systemImage: "qrcode") }
            }
        } footer: {
            Text("Пинг — TCP-доступность самого сервера. SNI — не режет ли DPI имя из поля sni. Проверки можно запускать повторно.")
        }
    }

    // MARK: Input

    private var inputSection: some View {
        Section {
            TextField("URL, содержимое или happ:// / incy:// ссылка", text: $model.input, axis: .vertical)
                .lineLimit(1...4)
                .font(.callout.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Picker("User-Agent", selection: $model.selectedUA) {
                ForEach(SubscriptionUserAgents.all) { ua in Text(ua.label).tag(ua) }
            }
            HStack(spacing: 14) {
                Button { if let s = clipboard() { model.input = s } } label: {
                    Label("Вставить", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                savedMenu
                Spacer()
                Button { Task { await model.resolveAndParse() } } label: {
                    if model.loading { ProgressView() } else { Label("Разобрать", systemImage: "arrow.right.circle.fill") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.loading || model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } footer: {
            if let error = model.error {
                Label(LocalizedStringKey(error), systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
        }
    }

    /// Sort control + a filter menu per facet that actually varies. Only the
    /// selected value narrows the list; picking "All" clears that facet.
    private var filterSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        Picker("Сортировка", selection: $model.sort) {
                            ForEach(ServerSort.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        filterChip(icon: "arrow.up.arrow.down", text: model.sort.title, active: false)
                    }

                    ForEach(model.availableFacets) { facet in
                        Menu {
                            Button { model.filters[facet] = nil } label: {
                                if model.filters[facet] == nil { Label("Все", systemImage: "checkmark") } else { Text("Все") }
                            }
                            Divider()
                            ForEach(model.facetValues(facet), id: \.self) { value in
                                Button { model.filters[facet] = value } label: {
                                    let label = facetValueLabel(facet, value)
                                    if model.filters[facet] == value { Label(label, systemImage: "checkmark") } else { Text(label) }
                                }
                            }
                        } label: {
                            filterChip(icon: facet.icon,
                                       text: model.filters[facet].map { "\(facet.title): \(facetValueLabel(facet, $0))" } ?? facet.title,
                                       active: model.filters[facet] != nil)
                        }
                    }

                    if !model.filters.isEmpty {
                        Button { model.filters.removeAll() } label: {
                            filterChip(icon: "xmark", text: "Сбросить", active: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
    }

    /// Pretty display for a facet value — country flags get their name appended.
    private func facetValueLabel(_ facet: ServerFacet, _ value: String) -> String {
        facet == .country ? CountryFlag.label(forFlag: value) : value
    }

    private func filterChip(icon: String, text: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.subheadline.weight(.medium)).lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: Capsule())
        .foregroundStyle(active ? Color.white : Color.primary)
    }

    private func formatLabel(_ f: SubscriptionFormat) -> String {
        switch f {
        case .base64List: "base64"
        case .plainList: "список ссылок"
        case .clash: "Clash"
        case .singbox: "sing-box"
        case .xray: "Xray JSON"
        case .unknown: "неизвестно"
        }
    }

    private func clipboard() -> String? {
        #if os(iOS)
        return UIPasteboard.general.string
        #elseif os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #else
        return nil
        #endif
    }
}

/// One server row: flag · remark · badges · ping · SNI-check.
private struct ServerRow: View {
    let node: ProxyNode
    @Bindable var model: SubscriptionModel
    let onOpen: () -> Void

    var body: some View {
        let (flag, title) = CountryFlag.split(node.name)
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    Text(flag).font(.title2).frame(width: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                        HStack(spacing: 5) {
                            badge(node.proto.rawValue.uppercased(), color: protoColor)
                            badge(formatBadge, color: .orange.opacity(0.9))
                            Text(node.network.uppercased()).font(.caption2).foregroundStyle(.secondary)
                            Text("·").foregroundStyle(.tertiary).font(.caption2)
                            Text(securityLabel).font(.caption2.weight(.medium))
                                .foregroundStyle(node.isReality ? .teal : .secondary)
                            if node.isMultihost {
                                badge("×\(node.children.count)", color: .indigo)
                            }
                        }
                        // The two things an operator actually needs at a glance.
                        if node.isMultihost {
                            Text("Мультихост · \(node.children.count) серверов")
                                .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        } else {
                            Text("\(node.host):\(String(node.port))")
                                .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                            if !node.sni.isEmpty {
                                Text("SNI: \(node.sni)")
                                    .font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            VStack(alignment: .trailing, spacing: 6) {
                pingView
                sniButton
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button { Task { await model.ping(node) } } label: { Label("Пинг", systemImage: "bolt.horizontal") }
            if !node.sni.isEmpty {
                Button { Task { await model.checkSNI(node) } } label: { Label("Проверить SNI", systemImage: "checkmark.shield") }
            }
            Button { copy(node.raw) } label: { Label("Скопировать ссылку", systemImage: "doc.on.doc") }
        }
    }

    /// Always a button — a finished result can be re-measured by tapping it.
    @ViewBuilder private var pingView: some View {
        if model.pingInFlight.contains(node.id) {
            ProgressView().controlSize(.small)
        } else {
            Button { Task { await model.ping(node) } } label: {
                switch model.pings[node.id] {
                case .ms(let ms):
                    Text("\(Int(ms.rounded()))ms").font(.callout.monospacedDigit()).foregroundStyle(pingColor(ms))
                case .fail:
                    Text("n/a").font(.callout).foregroundStyle(.red)
                case nil:
                    Image(systemName: "bolt.horizontal.circle").foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Проверить доступность ещё раз")
        }
    }

    @ViewBuilder private var sniButton: some View {
        if node.sni.isEmpty {
            EmptyView()
        } else if model.sniInFlight.contains(node.id) {
            ProgressView().controlSize(.small)
        } else {
            Button { Task { await model.checkSNI(node) } } label: {
                Image(systemName: model.snis[node.id].map(sniIcon) ?? "shield.lefthalf.filled")
                    .foregroundStyle(model.snis[node.id].map(sniColor) ?? .secondary)
                    .font(.footnote)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Проверить блокировку SNI ещё раз")
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text).font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(color)
    }

    private var formatBadge: String {
        switch model.format {
        case .xray, .singbox: "JSON"
        case .clash: "CLASH"
        case .base64List, .plainList: "LINK"
        case .unknown: "?"
        }
    }
    private var securityLabel: String { node.isReality ? "REALITY" : node.security.uppercased() }
    private var protoColor: Color {
        switch node.proto {
        case .vless: .blue
        case .trojan: .purple
        case .vmess: .orange
        case .shadowsocks: .green
        case .hysteria2, .tuic: .pink
        case .unknown: .gray
        }
    }
    private func pingColor(_ ms: Double) -> Color { ms < 100 ? .green : ms < 200 ? .blue : ms < 300 ? .yellow : .orange }
    private func sniIcon(_ v: CensorshipVerdict) -> String {
        switch v { case .clean: "checkmark.shield.fill"; case .restricted: "xmark.shield.fill"; case .inconclusive: "questionmark.diamond" }
    }
    private func sniColor(_ v: CensorshipVerdict) -> Color {
        switch v { case .clean: .green; case .restricted: .red; case .inconclusive: .gray }
    }

    private func copy(_ s: String) {
        #if os(iOS)
        UIPasteboard.general.string = s
        #elseif os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
        #endif
    }
}

/// Full server details: every parsed field, the raw config block (JSON or link),
/// a JSON-validity check and copy-to-clipboard.
private struct ServerDetailView: View {
    let node: ProxyNode
    @Bindable var model: SubscriptionModel
    @State private var showRaw = true
    @State private var qr: QRPayload?
    @State private var childDetail: ProxyNode?
    @State private var ipOverviewHost: String?
    @Environment(XrayCoreStore.self) private var cores

    private var rawIsJSON: Bool {
        let t = node.raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("{") || t.hasPrefix("[")
    }
    /// Validity of the raw block — checked eagerly, not on demand.
    private var jsonValid: Bool? {
        guard rawIsJSON, let data = node.raw.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    var body: some View {
        List {
            // Multihost: list of nested servers, each opens separately.
            if node.isMultihost {
                Section {
                    ForEach(node.children) { child in
                        Button { childDetail = child } label: {
                            HStack(spacing: 10) {
                                let (flag, title) = CountryFlag.split(child.name)
                                Text(flag)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title).foregroundStyle(.primary).lineLimit(1)
                                    Text("\(child.host):\(String(child.port)) · \(child.isReality ? "REALITY" : child.security.uppercased())")
                                        .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Серверы внутри · \(node.children.count)")
                } footer: {
                    Text("Этот хост объединяет несколько прокси. Проверки ниже относятся к основному (первому) серверу.")
                }
            }

            // Order: address → how we connect → TLS details.
            Section {
                Button { ipOverviewHost = node.host } label: {
                    HStack {
                        InfoRow(label: "Хост", value: node.host, mono: true)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                InfoRow(label: "Порт", value: String(node.port), mono: true)
            } header: {
                Text("Адрес")
            } footer: {
                Text("Нажмите на хост, чтобы посмотреть провайдера, страну и ASN.")
            }
            Section("Подключение") {
                InfoRow(label: "Протокол", value: node.proto.rawValue.uppercased())
                InfoRow(label: "Транспорт", value: node.network.uppercased())
                InfoRow(label: "Безопасность", value: node.isReality ? "REALITY" : node.security.uppercased(),
                        valueColor: node.isReality ? .teal : .primary)
            }
            if !node.sni.isEmpty || !node.flow.isEmpty {
                Section("TLS") {
                    if !node.sni.isEmpty { InfoRow(label: "SNI", value: node.sni, mono: true) }
                    if !node.flow.isEmpty { InfoRow(label: "Flow", value: node.flow, mono: true) }
                }
            }
            if !node.extras.isEmpty {
                Section {
                    ForEach(node.extras) { p in
                        InfoRow(label: p.key, value: p.value, mono: true)
                    }
                } header: {
                    Text("Параметры · \(node.extras.count)")
                } footer: {
                    Text("Всё, что пришло помимо основных полей: fingerprint, pbk/sid, alpn, mux, sockopt, xhttp extra, route и т. д.")
                }
            }
            Section("Имя") {
                InfoRow(label: "Remark", value: node.name)
            }

            Section {
                // Ping (TCP)
                checkRow("Пинг", systemImage: "bolt.horizontal.circle",
                         running: model.pingInFlight.contains(node.id),
                         hasResult: model.pings[node.id] != nil,
                         action: { Task { await model.ping(node) } }) {
                    switch model.pings[node.id] {
                    case .ms(let ms): Text("\(Int(ms.rounded())) ms").foregroundStyle(pingColor(ms))
                    case .fail: Text("n/a").foregroundStyle(.red)
                    case nil: EmptyView()
                    }
                }
                // SNI blocking
                if !node.sni.isEmpty {
                    checkRow("SNI", systemImage: "checkmark.shield",
                             running: model.sniInFlight.contains(node.id),
                             hasResult: model.snis[node.id] != nil,
                             action: { Task { await model.checkSNI(node) } }) {
                        if let v = model.snis[node.id] {
                            Text(verdictShort(v)).foregroundStyle(verdictColor(v))
                        }
                    }
                }
                // Native TLS/Reality handshake
                checkRow("Рукопожатие", systemImage: "hand.wave",
                         running: model.handshakeInFlight.contains(node.id),
                         hasResult: model.handshakes[node.id] != nil,
                         action: { Task { await model.handshakePing(node) } }) {
                    if let h = model.handshakes[node.id] {
                        Text(h.reaction == .serverHello ? "\(Int(h.ms.rounded())) ms" : shortReaction(h.reaction))
                            .foregroundStyle(handshakeColor(h.reaction))
                    }
                }
                // Through proxy (macOS)
                proxyCheckRow
            } header: {
                Text("Проверки")
            } footer: {
                Text("Рукопожатие — TLS-ответ по dest-SNI (ловит блокировку SNI). Через прокси (Mac) — реальный запрос к gstatic через тоннель. Всё можно перезапускать.")
            }

            Section {
                DisclosureGroup("Блок этого сервера", isExpanded: $showRaw) {
                    Text(node.raw)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // The full Xray config the client receives for this specific host
                // (dns + routing + outbounds), not just its outbound.
                if let full = node.fullConfig {
                    DisclosureGroup("Полный Xray JSON этого хоста") {
                        Text(full)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button { copy(full) } label: {
                        Label("Скопировать полный JSON", systemImage: "doc.on.doc.fill")
                    }
                }
                Button { copy(node.raw) } label: {
                    Label("Скопировать блок", systemImage: "doc.on.doc")
                }
                if !model.rawContent.isEmpty {
                    Button { copy(model.rawContent) } label: {
                        Label("Скопировать всю подписку", systemImage: "doc.on.clipboard")
                    }
                }
                // QR only makes sense for a real link: scanning a JSON block into
                // a client is useless. We don't share the whole subscription from
                // here — the main list has an action for that.
                if node.raw.contains("://") {
                    Button { qr = QRPayload(title: "Сервер", text: node.raw) } label: {
                        Label("Поделиться сервером (QR)", systemImage: "qrcode")
                    }
                }
            } header: {
                HStack {
                    Text("Исходные данные")
                    Spacer()
                    if let ok = jsonValid {
                        Label(ok ? "JSON валиден" : "JSON битый",
                              systemImage: ok ? "checkmark.seal.fill" : "xmark.seal.fill")
                            .font(.caption).foregroundStyle(ok ? .green : .red)
                    } else {
                        Text("ссылка").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(CountryFlag.split(node.name).title)
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $qr) { QRShareSheet(payload: $0) }
        .navigationDestination(item: $childDetail) { child in
            ServerDetailView(node: child, model: model)
        }
        .navigationDestination(item: $ipOverviewHost) { host in
            IPLocationView(presetHost: host, autostart: true)
                .navigationTitle("Обзор IP")
        }
    }

    /// One compact check row: icon + short title on the left, a short colored
    /// result and a small run/refresh button on the right. Nothing wraps.
    @ViewBuilder
    private func checkRow<Value: View>(
        _ title: LocalizedStringKey, systemImage: String,
        running: Bool, hasResult: Bool, action: @escaping () -> Void,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(.tint).frame(width: 22)
            Text(title).lineLimit(1)
            Spacer(minLength: 8)
            value().font(.callout.monospacedDigit()).lineLimit(1)
            if running {
                ProgressView().controlSize(.small)
            } else {
                Button(action: action) {
                    Image(systemName: hasResult ? "arrow.clockwise" : "play.circle.fill")
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(hasResult ? "Проверить ещё раз" : "Проверить")
            }
        }
    }

    /// Through-proxy check row (macOS). On iOS it's absent — the handshake row
    /// is the native equivalent.
    @ViewBuilder private var proxyCheckRow: some View {
        #if os(macOS)
        if let core = cores.installed.first?.binary {
            checkRow("Через прокси", systemImage: "arrow.triangle.swap",
                     running: model.proxyInFlight.contains(node.id),
                     hasResult: model.proxyPings[node.id] != nil,
                     action: { Task { await model.proxyPing(node, coreBinary: core) } }) {
                switch model.proxyPings[node.id] {
                case .ms(let ms, let status):
                    Text("\(Int(ms.rounded())) ms")
                        .foregroundStyle(status == 204 || status == 200 ? .green : .orange)
                case .fail: Text("ошибка").foregroundStyle(.red)
                case nil: EmptyView()
                }
            }
        } else {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.swap").foregroundStyle(.tint).frame(width: 22)
                Text("Через прокси").lineLimit(1)
                Spacer(minLength: 8)
                Text("нужно ядро").font(.caption).foregroundStyle(.secondary)
            }
        }
        #else
        EmptyView()
        #endif
    }

    private func pingColor(_ ms: Double) -> Color { ms < 100 ? .green : ms < 200 ? .blue : ms < 300 ? .yellow : .orange }

    private func handshakeColor(_ r: JA3ProbeResult.Reaction) -> Color {
        switch r {
        case .serverHello: .green
        case .tlsAlert: .yellow
        case .reset, .timeout: .red
        case .closed, .tcpFailed: .secondary
        }
    }

    private func shortReaction(_ r: JA3ProbeResult.Reaction) -> String {
        switch r {
        case .serverHello: "OK"
        case .tlsAlert: "alert"
        case .reset: "RST"
        case .timeout: "таймаут"
        case .closed: "закрыто"
        case .tcpFailed: "нет TCP"
        }
    }

    private func verdictText(_ v: CensorshipVerdict) -> String {
        switch v { case .clean: "не блокируется"; case .restricted: "блокируется"; case .inconclusive: "не определено" }
    }
    private func verdictShort(_ v: CensorshipVerdict) -> String {
        switch v { case .clean: "чисто"; case .restricted: "блок"; case .inconclusive: "?" }
    }
    private func verdictColor(_ v: CensorshipVerdict) -> Color {
        switch v { case .clean: .green; case .restricted: .red; case .inconclusive: .gray }
    }
    private func copy(_ s: String) {
        #if os(iOS)
        UIPasteboard.general.string = s
        #elseif os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
        #endif
    }
}

/// What to show in the QR — the whole subscription or a specific server's link.
struct QRPayload: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

/// Shared sheet with a QR code and copy — used both for a subscription
/// and for an individual server's link.
struct QRShareSheet: View {
    let payload: QRPayload
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    QRCodeView(text: payload.text)
                        .frame(maxWidth: 280)
                    Text(payload.text)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button {
                        #if os(iOS)
                        UIPasteboard.general.string = payload.text
                        #elseif os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(payload.text, forType: .string)
                        #endif
                    } label: { Label("Скопировать", systemImage: "doc.on.doc") }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle(LocalizedStringKey(payload.title))
            #if os(iOS)
            .toolbarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
