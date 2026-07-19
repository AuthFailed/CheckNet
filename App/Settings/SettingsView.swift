import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SavedHostsStore.self) private var savedHosts
    @State private var showHistory = false
    @State private var permissionResult: String?

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("Оформление") {
                    Picker("Тема", selection: $settings.theme) {
                        ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Язык", selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section("Сохранённые хосты") {
                    NavigationLink {
                        SavedHostsEditor(kind: .domain)
                    } label: {
                        Label {
                            LabeledContent("Домены", value: "\(savedHosts.savedDomains.count)")
                        } icon: { Image(systemName: "globe") }
                    }
                    NavigationLink {
                        SavedHostsEditor(kind: .ip)
                    } label: {
                        Label {
                            LabeledContent("IP-адреса", value: "\(savedHosts.savedIPs.count)")
                        } icon: { Image(systemName: "number") }
                    }
                }

                Section("Проверки") {
                    Toggle("Live Activity в Dynamic Island", isOn: $settings.liveActivitiesEnabled)
                    Toggle("Обратный DNS по умолчанию", isOn: $settings.reverseDNSByDefault)
                    Button {
                        showHistory = true
                    } label: {
                        Label("История проверок", systemImage: "clock.arrow.circlepath")
                    }
                }

                Section {
                    Button {
                        LocalNetworkPermission.shared.request { granted in
                            permissionResult = granted ? "Доступ к локальной сети активен." : "Доступ к локальной сети не подтверждён — разрешите его в Настройках iOS."
                        }
                    } label: {
                        Label("Запросить доступ к локальной сети", systemImage: "wifi")
                    }
                    if let permissionResult {
                        Text(permissionResult).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Разрешения")
                } footer: {
                    Text("Сканер сети, обзор устройств и Bonjour требуют доступа к локальной сети. На iOS без него проверки могут молча не работать.")
                }

                Section("О приложении") {
                    LabeledContent("Версия", value: appVersion)
                    LabeledContent("Инструментов", value: "\(Tool.allCases.filter(\.isImplemented).count)")
                    Link(destination: URL(string: "https://ru.wikipedia.org/wiki/Ping")!) {
                        Label("Как работают проверки", systemImage: "questionmark.circle")
                    }
                }
            }
            .navigationTitle("Настройки")
            .sheet(isPresented: $showHistory) { HistoryView() }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

/// Add/edit/delete saved hosts of one kind (IP or domain).
struct SavedHostsEditor: View {
    enum Kind { case ip, domain
        var title: String { self == .ip ? "IP-адреса" : "Домены" }
        var placeholder: String { self == .ip ? "8.8.8.8" : "example.com" }
        var icon: String { self == .ip ? "number" : "globe" }
    }
    let kind: Kind
    @Environment(SavedHostsStore.self) private var store
    @State private var newName = ""
    @State private var newValue = ""

    private var items: [SavedHost] { kind == .ip ? store.savedIPs : store.savedDomains }

    var body: some View {
        Form {
            Section("Добавить") {
                TextField("Название (необязательно)", text: $newName)
                HStack {
                    Image(systemName: kind.icon).foregroundStyle(.secondary)
                    TextField(kind.placeholder, text: $newValue)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(kind == .ip ? .numbersAndPunctuation : .URL)
                        #endif
                }
                Button("Сохранить") { add() }
                    .disabled(!isValid)
            }

            Section("Сохранённые") {
                if items.isEmpty {
                    Text("Пока пусто").foregroundStyle(.secondary)
                } else {
                    ForEach(items) { host in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(host.name).font(.body)
                            Text(host.value).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { store.remove(items[i]) }
                    }
                }
            }
        }
        .navigationTitle(kind.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var isValid: Bool {
        let v = newValue.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return false }
        return kind == .ip ? SavedHostsStore.isIP(v) : !SavedHostsStore.isIP(v) && v.contains(".")
    }

    private func add() {
        store.add(name: newName, value: newValue, tool: nil)
        newName = ""; newValue = ""
    }
}
