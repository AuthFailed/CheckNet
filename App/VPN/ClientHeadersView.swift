import SwiftUI
import NetworkKit

/// One client identity the user can edit: app name + version compose the
/// `User-Agent`. Persisted so custom versions stick between sessions.
struct EditableClient: Identifiable, Codable, Equatable {
    var id: String
    var app: String
    var version: String
    var enabled: Bool = true
    /// Preset id used to resolve a GitHub repo; nil for user-added rows.
    var presetID: String?

    var userAgent: String {
        version.trimmingCharacters(in: .whitespaces).isEmpty
            ? app : "\(app)/\(version.trimmingCharacters(in: .whitespaces))"
    }
    /// `owner/repo` on GitHub, if this client is open source.
    var repo: String? { ClientReleaseIndex.repo(clientID: presetID, product: app) }

    static func splitUA(_ ua: String) -> (app: String, version: String) {
        guard let slash = ua.lastIndex(of: "/") else { return (ua, "") }
        return (String(ua[..<slash]), String(ua[ua.index(after: slash)...]))
    }

    /// The built-in clients (v2rayNG, Happ, Clash Meta…) as editable rows.
    static func defaults() -> [EditableClient] {
        SubscriptionUserAgents.all.compactMap { ua in
            guard let header = ua.header else { return nil }
            let parts = splitUA(header)
            return EditableClient(id: ua.id, app: parts.app, version: parts.version,
                                  enabled: true, presetID: ua.id)
        }
    }
}

@MainActor
@Observable
final class ClientHeadersModel {
    var url = ""
    var clients: [EditableClient] = ClientHeadersModel.loadClients() ?? EditableClient.defaults()
    /// HWID (device id) some panels bind subscriptions to. Off by default.
    var sendHWID = UserDefaults.standard.bool(forKey: "checknet.vpn.sendHWID")
    var hwid = UserDefaults.standard.string(forKey: "checknet.vpn.hwid") ?? ""
    /// Fetched GitHub versions, keyed by `owner/repo`.
    var githubVersions: [String: [String]] = [:]
    private(set) var loadingVersions = false
    var versionsNote: String?
    private(set) var isRunning = false
    private(set) var results: [ClientProbeResult] = []
    private(set) var served = 0
    private(set) var total = 0
    private(set) var errorMessage: String?
    private var task: Task<Void, Never>?

    private static let storeKey = "checknet.vpn.clientHeaders"

    /// Enabled rows, in list order, as the probe's client set.
    private func probeClients() -> [SubscriptionUserAgent] {
        clients.filter { $0.enabled && !$0.app.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { SubscriptionUserAgent(id: $0.id, label: $0.app, header: $0.userAgent) }
    }

    private func order() -> [String: Int] {
        Dictionary(uniqueKeysWithValues: clients.enumerated().map { ($1.id, $0) })
    }

    func start() {
        let u = url.trimmingCharacters(in: .whitespaces)
        let clientSet = probeClients()
        guard !u.isEmpty, !clientSet.isEmpty else { return }
        stop()
        results = []; served = 0; total = 0; errorMessage = nil; isRunning = true
        let rank = order()
        let hwidToSend = (sendHWID && !hwid.trimmingCharacters(in: .whitespaces).isEmpty)
            ? hwid.trimmingCharacters(in: .whitespaces) : nil
        task = Task { [weak self] in
            guard let self else { return }
            for await event in ClientHeaderProbe.probe(urlString: u, clients: clientSet, hwid: hwidToSend) {
                if Task.isCancelled { break }
                switch event {
                case .result(let r):
                    results.append(r)
                    results.sort { (rank[$0.clientID] ?? 99) < (rank[$1.clientID] ?? 99) }
                case .finished(let s, let t):
                    served = s; total = t
                case .failed(let reason):
                    errorMessage = reason
                }
            }
            isRunning = false
        }
    }

    func stop() { task?.cancel(); task = nil; isRunning = false }

    // MARK: - Client editing

    func addClient() {
        clients.append(EditableClient(id: "custom-\(clients.count)-\(UUID().uuidString.prefix(4))",
                                      app: "", version: "", enabled: true, presetID: nil))
    }

    func remove(atOffsets offsets: IndexSet) { clients.remove(atOffsets: offsets); saveClients() }

    func resetClients() {
        clients = EditableClient.defaults()
        githubVersions = [:]; versionsNote = nil
        saveClients()
    }

    /// Pulls the latest release list from GitHub for every open-source client and
    /// fills each with its newest version. Leaves closed-source clients as-is.
    func loadVersionsFromGitHub() async {
        guard !loadingVersions else { return }
        loadingVersions = true; versionsNote = nil
        let repos = Set(clients.compactMap { $0.repo })
        guard !repos.isEmpty else {
            loadingVersions = false
            versionsNote = "Ни один клиент не связан с GitHub-репозиторием."
            return
        }
        var updated = 0
        for repo in repos {
            if let versions = try? await ClientReleaseIndex.versions(repo: repo) {
                githubVersions[repo] = versions
            }
        }
        for i in clients.indices {
            if let repo = clients[i].repo, let latest = githubVersions[repo]?.first {
                clients[i].version = latest
                updated += 1
            }
        }
        saveClients()
        loadingVersions = false
        versionsNote = updated > 0
            ? "Обновлено версий: \(updated) из GitHub."
            : "Не удалось получить версии — проверьте сеть."
    }

    func saveClients() {
        if let data = try? JSONEncoder().encode(clients) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }

    func saveHWID() {
        UserDefaults.standard.set(sendHWID, forKey: "checknet.vpn.sendHWID")
        UserDefaults.standard.set(hwid, forKey: "checknet.vpn.hwid")
    }

    /// A plausible random device id for panels that expect one.
    func generateHWID() {
        hwid = UUID().uuidString.lowercased()
        saveHWID()
    }

    static func loadClients() -> [EditableClient]? {
        UserDefaults.standard.data(forKey: storeKey)
            .flatMap { try? JSONDecoder().decode([EditableClient].self, from: $0) }
    }
}

/// Ответ сервера подписки на заголовки разных клиентов (#75). Вводим URL
/// подписки, запрашиваем его от лица каждого клиента (Happ, v2rayNG, Clash,
/// sing-box…) и показываем, что сервер отдаёт каждому: статус, число узлов,
/// формат и заголовки панели (`subscription-userinfo`, `content-disposition`,
/// `profile-*`). Диагностика — просто повтор своей подписки под разными именами.
struct ClientHeadersView: View {
    var autostart = false
    @State private var model = ClientHeadersModel()
    @State private var showEditor = false
    @Environment(SavedSubscriptionsStore.self) private var saved

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $model.url, placeholder: "URL подписки",
                         icon: "person.2.badge.gearshape", disabled: model.isRunning) {
                model.start()
            } trailing: {
                AnyView(savedMenu)
            }

            if let error = model.errorMessage {
                ErrorCard(message: error) { model.start() }
            } else if model.total > 0 || model.isRunning {
                summaryCard
            }
        } content: {
            if !model.results.isEmpty {
                ForEach(model.results) { result in
                    resultCard(result)
                }
            } else if model.isRunning {
                ProgressView().padding(.top, 40)
            } else if model.errorMessage == nil {
                ToolIdleHint(
                    icon: "person.2.badge.gearshape",
                    title: "Ответ сервера по клиентам",
                    message: "Запросим подписку от лица разных клиентов и покажем, что сервер отдаёт каждому: узлы, формат, лимиты и имя файла.",
                    example: "https://example.com/sub",
                    current: model.url
                ) { model.url = "https://example.com/sub" }
            }
        } bottom: {
            RunButton(title: "Запросить", running: model.isRunning,
                      disabled: model.url.trimmingCharacters(in: .whitespaces).isEmpty) {
                if model.isRunning { model.stop() } else { model.start() }
            }
        }
        .animation(.snappy, value: model.results)
        .haptic(.success, trigger: model.isRunning) { !$0 && model.errorMessage == nil }
        .haptic(.failure, trigger: model.isRunning) { !$0 && model.errorMessage != nil }
        .navigationTitle("Заголовки клиентов")
        .toolTitleDisplayMode()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEditor = true
                } label: {
                    Label("Клиенты и версии", systemImage: "slider.horizontal.3")
                }
                .disabled(model.isRunning)
            }
        }
        .sheet(isPresented: $showEditor) {
            ClientEditorView(model: model)
        }
        .onAppear { if autostart { model.start() } }
    }

    /// Same saved-subscriptions list the «Парсинг подписки» tool uses — pick one
    /// to substitute, or bookmark the current URL.
    @ViewBuilder private var savedMenu: some View {
        Menu {
            if !saved.items.isEmpty {
                Section("Сохранённые") {
                    ForEach(saved.items) { item in
                        Button { model.url = item.value } label: {
                            Label(item.name, systemImage: "list.bullet.rectangle")
                        }
                    }
                }
            }
            let current = model.url.trimmingCharacters(in: .whitespacesAndNewlines)
            if !current.isEmpty, !saved.contains(current) {
                Button { saved.add(name: "", value: current) } label: {
                    Label("Сохранить эту подписку", systemImage: "bookmark")
                }
            }
        } label: {
            Image(systemName: "bookmark")
        }
        .accessibilityLabel("Сохранённые подписки")
        .disabled(saved.items.isEmpty && model.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var summaryCard: some View {
        HStack {
            Text("\(model.served) обслужено").font(.headline).foregroundStyle(.green)
            Spacer()
            if model.isRunning {
                ProgressView()
            } else {
                Text("\(model.results.count) / \(model.total) клиентов")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(14).card()
    }

    private func resultCard(_ r: ClientProbeResult) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                StatusDot(level: level(r), label: LocalizedStringKey(statusWord(r)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.clientLabel).font(.callout.weight(.medium))
                    Text(r.userAgent).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(statusBadge(r))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(level(r).badgeColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(level(r).badgeColor.opacity(0.14), in: Capsule())
            }
            .padding(.horizontal, 14).padding(.vertical, 11)

            if let details = detailRows(r), !details.isEmpty {
                Divider().padding(.leading, 14)
                VStack(spacing: 0) {
                    ForEach(details, id: \.0) { row in
                        InfoRow(label: row.0, value: row.1)
                        if row.0 != details.last?.0 { Divider().padding(.leading, 14) }
                    }
                }
            }

            if !r.responseHeaders.isEmpty {
                Divider().padding(.leading, 14)
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(r.responseHeaders.sorted { $0.key < $1.key }, id: \.key) { key, value in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(key).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                Text(value).font(.caption2.monospaced())
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text("Заголовки ответа (\(r.responseHeaders.count))")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
            }
        }
        .card()
    }

    // MARK: - Result → view data

    private func level(_ r: ClientProbeResult) -> StatusDot.Level {
        if r.errorText != nil { return .bad }
        if r.isServed { return .ok }
        if (200..<300).contains(r.statusCode) { return .warning }   // 2xx but no nodes
        return .bad
    }

    private func statusWord(_ r: ClientProbeResult) -> String {
        if r.errorText != nil { return "ошибка" }
        if r.isServed { return "обслужен" }
        if (200..<300).contains(r.statusCode) { return "без узлов" }
        return "отказ"
    }

    private func statusBadge(_ r: ClientProbeResult) -> String {
        if let err = r.errorText { return err }
        if r.nodeCount > 0 { return "\(r.statusCode) · \(r.nodeCount) узл." }
        return "\(r.statusCode)"
    }

    private func detailRows(_ r: ClientProbeResult) -> [(String, String)]? {
        guard r.errorText == nil else { return nil }
        var rows: [(String, String)] = []
        if let format = r.format { rows.append(("Формат", format)) }
        rows.append(("Размер", Int64(r.byteCount).formatted(.byteCount(style: .binary))))
        if let title = r.title { rows.append(("Название", title)) }
        if let file = r.filename { rows.append(("Файл", file)) }
        if let h = r.updateIntervalHours {
            rows.append(("Обновление", "\(Int(h)) ч"))
        }
        if let info = r.userInfo, info.hasData {
            if let total = info.totalBytes {
                let used = (info.uploadBytes ?? 0) + (info.downloadBytes ?? 0)
                rows.append(("Трафик", "\(Int64(used).formatted(.byteCount(style: .binary))) / \(total.formatted(.byteCount(style: .binary)))"))
            }
            if let expire = info.expire {
                rows.append(("Действует до", expire.formatted(date: .abbreviated, time: .omitted)))
            }
        }
        if let support = r.supportURL { rows.append(("Поддержка", support)) }
        return rows
    }
}

private extension StatusDot.Level {
    var badgeColor: Color {
        switch self {
        case .ok: .green
        case .warning: .orange
        case .bad: .red
        case .unknown: .gray
        }
    }
}
