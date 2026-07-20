import SwiftUI

/// Pick which saved hosts to share, then hand them off as a link, a QR code or
/// clipboard text. Also the entry point for importing a link someone sent you.
struct HostSharingView: View {
    enum Scope: Int, CaseIterable, Identifiable {
        case all, domains, ips
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .all: "Все"
            case .domains: "Домены"
            case .ips: "IP-адреса"
            }
        }
    }

    @Environment(SavedHostsStore.self) private var store
    @State private var scope: Scope = .all
    @State private var selection: Set<UUID> = []
    @State private var showQR = false
    @State private var copied = false
    @State private var pendingImport: ImportPayload?
    @State private var pasteError: String?
    @State private var didSeedSelection = false
    @State private var showScanner = false
    /// Hosts decoded from a scan, held until the camera sheet has closed so the
    /// import sheet doesn't try to present on top of it.
    @State private var scannedHosts: [SavedHost]?

    private var globalHosts: [SavedHost] {
        store.hosts.filter { $0.toolID == nil }
    }

    private var visibleHosts: [SavedHost] {
        switch scope {
        case .all: globalHosts
        case .domains: store.savedDomains
        case .ips: store.savedIPs
        }
    }

    private var selectedHosts: [SavedHost] {
        globalHosts.filter { selection.contains($0.id) }
    }

    private var shareURL: URL? { HostSharing.url(for: selectedHosts) }

    var body: some View {
        Form {
            if globalHosts.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Нет сохранённых хостов",
                        systemImage: "bookmark",
                        description: Text("Добавьте домены или IP-адреса, чтобы поделиться ими.")
                    )
                }
            } else {
                Section {
                    Picker("Показывать", selection: $scope) {
                        ForEach(Scope.allCases) { Text(LocalizedStringKey($0.label)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    ForEach(visibleHosts) { host in
                        Button { toggle(host) } label: { row(for: host) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("Что отправить")
                        Spacer()
                        Button(allVisibleSelected ? "Снять все" : "Выбрать все") {
                            toggleAllVisible()
                        }
                        .font(.caption)
                        .textCase(nil)
                    }
                } footer: {
                    Text("Выбрано: \(selection.count)")
                }

                Section {
                    if let shareURL {
                        ShareLink(item: shareURL) {
                            Label("Поделиться ссылкой", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            showQR = true
                        } label: {
                            Label("Показать QR-код", systemImage: "qrcode")
                        }
                        Button {
                            Pasteboard.copy(shareURL.absoluteString)
                            copied = true
                        } label: {
                            Label(copied ? "Ссылка скопирована" : "Скопировать ссылку",
                                  systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                    } else {
                        Text("Выберите хотя бы один хост").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Отправить")
                } footer: {
                    Text("Ссылка содержит только выбранные хосты. Она открывается в CheckNet на другом устройстве и ничего не отправляет в интернет.")
                }
            }

            Section {
                #if os(iOS)
                Button {
                    pasteError = nil
                    showScanner = true
                } label: {
                    Label("Сканировать QR-код", systemImage: "qrcode.viewfinder")
                }
                #endif
                Button {
                    importFromClipboard()
                } label: {
                    Label("Вставить ссылку из буфера", systemImage: "doc.on.clipboard")
                }
                if let pasteError {
                    Text(LocalizedStringKey(pasteError)).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Импорт")
            } footer: {
                Text("Отсканируйте QR-код с другого устройства или скопируйте присланную ссылку checknet:// — приложение покажет, что именно будет добавлено.")
            }
        }
        .navigationTitle("Поделиться хостами")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear(perform: seedSelectionOnce)
        .onChange(of: selection) { _, _ in copied = false }
        .sheet(isPresented: $showQR) {
            if let shareURL {
                QRSharePosterView(url: shareURL, count: selectedHosts.count)
            }
        }
        .sheet(item: $pendingImport) { payload in
            ImportHostsSheet(hosts: payload.hosts)
        }
        #if os(iOS)
        .sheet(isPresented: $showScanner, onDismiss: presentScannedHosts) {
            QRScannerSheet(onFound: handleScan)
        }
        #endif
    }

    private func handleScan(_ payload: String) {
        guard let hosts = HostSharing.hosts(fromPastedText: payload), !hosts.isEmpty else {
            pasteError = "В этом QR-коде нет списка хостов CheckNet."
            return
        }
        scannedHosts = hosts
    }

    private func presentScannedHosts() {
        guard let hosts = scannedHosts else { return }
        scannedHosts = nil
        pendingImport = ImportPayload(hosts: hosts)
    }

    private func row(for host: SavedHost) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selection.contains(host.id) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selection.contains(host.id) ? Color.accentColor : .secondary)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.name)
                Text(host.value).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: SavedHostsStore.isIP(host.value) ? "number" : "globe")
                .foregroundStyle(.tertiary)
                .font(.caption)
        }
        .contentShape(.rect)
        .accessibilityAddTraits(selection.contains(host.id) ? [.isSelected, .isButton] : .isButton)
    }

    private var allVisibleSelected: Bool {
        !visibleHosts.isEmpty && visibleHosts.allSatisfy { selection.contains($0.id) }
    }

    private func toggle(_ host: SavedHost) {
        if selection.contains(host.id) { selection.remove(host.id) } else { selection.insert(host.id) }
    }

    private func toggleAllVisible() {
        if allVisibleSelected {
            for host in visibleHosts { selection.remove(host.id) }
        } else {
            for host in visibleHosts { selection.insert(host.id) }
        }
    }

    private func seedSelectionOnce() {
        guard !didSeedSelection else { return }
        didSeedSelection = true
        selection = Set(globalHosts.map(\.id))
    }

    private func importFromClipboard() {
        pasteError = nil
        guard let text = Pasteboard.string, !text.isEmpty else {
            pasteError = "Буфер обмена пуст."
            return
        }
        guard let hosts = HostSharing.hosts(fromPastedText: text), !hosts.isEmpty else {
            pasteError = "В буфере нет ссылки CheckNet."
            return
        }
        pendingImport = ImportPayload(hosts: hosts)
    }
}

/// Wraps a decoded host list so it can drive a `sheet(item:)`.
struct ImportPayload: Identifiable {
    let id = UUID()
    let hosts: [SavedHost]
}

// MARK: - QR poster

private struct QRSharePosterView: View {
    let url: URL
    let count: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                QRCodeView(text: url.absoluteString)
                    .frame(maxWidth: 320)
                Text("Хостов в коде: \(count)")
                    .font(.headline)
                Text("Отсканируйте камерой на другом устройстве с установленным CheckNet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding()
            .navigationTitle("QR-код")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Import

/// Preview of an incoming share link before anything is written to the store.
struct ImportHostsSheet: View {
    let hosts: [SavedHost]
    @Environment(SavedHostsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var result: (added: Int, skipped: Int)?

    private var newHosts: [SavedHost] { hosts.filter { !store.containsGlobally($0.value) } }
    private var duplicates: Int { hosts.count - newHosts.count }

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    Section {
                        Label("Добавлено: \(result.added)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if result.skipped > 0 {
                            Text("Пропущено дубликатов: \(result.skipped)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        LabeledContent("Новых", value: "\(newHosts.count)")
                        LabeledContent("Уже сохранено", value: "\(duplicates)")
                    } footer: {
                        Text("Импорт только добавляет хосты — существующие записи не изменяются и не удаляются.")
                    }

                    Section("Из ссылки") {
                        ForEach(hosts) { host in
                            HStack(spacing: 12) {
                                Image(systemName: SavedHostsStore.isIP(host.value) ? "number" : "globe")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(host.name)
                                    Text(host.value).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.containsGlobally(host.value) {
                                    Text("уже есть").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
            // Short title: "Импорт хостов" is truncated between the two toolbar buttons.
            .navigationTitle("Импорт")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if result == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Импортировать") { result = store.merge(hosts) }
                            .disabled(newHosts.isEmpty)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") { dismiss() }
                    }
                }
            }
        }
    }
}
