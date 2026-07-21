import SwiftUI
import NetworkKit

/// Manage per-network check profiles and run the one matching the current Wi-Fi.
struct NetworkProfilesView: View {
    @Environment(NetworkProfileStore.self) private var store
    @State private var editing: NetworkProfile?
    @State private var runState: RunState = .idle

    enum RunState: Equatable {
        case idle
        case reading
        case noMatch(ssid: String)
        case unavailable(reason: String)
        case running(ssid: String)
        case done(ssid: String, summary: String)
    }

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await runForCurrentNetwork() }
                } label: {
                    Label("Проверить текущую сеть", systemImage: "wifi")
                }
                .disabled(isBusy)
                statusRow
            } footer: {
                Text("Читает имя текущей Wi-Fi-сети и запускает профиль для неё. Для чтения имени сети нужны Wi-Fi-права приложения и разрешение на геопозицию (требование iOS).")
            }

            Section("Профили") {
                if store.profiles.isEmpty {
                    Text("Пока нет профилей").foregroundStyle(.secondary)
                } else {
                    ForEach(store.profiles) { profile in
                        Button { editing = profile } label: { profileRow(profile) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for i in offsets { store.remove(store.profiles[i]) }
                    }
                }
            }

            Section {
                Button {
                    editing = NetworkProfile(ssid: "", checkIDs: [])
                } label: {
                    Label("Добавить профиль", systemImage: "plus")
                }
            } footer: {
                Text("Автозапуск при подключении к сети настраивается в приложении «Команды»: автоматизация «При подключении к Wi-Fi …» → «Проверить блокировку». iOS не будит приложение на смену сети само.")
            }
        }
        .navigationTitle("Профили сети")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $editing) { profile in
            NetworkProfileEditor(profile: profile)
        }
    }

    private var isBusy: Bool {
        if case .reading = runState { return true }
        if case .running = runState { return true }
        return false
    }

    @ViewBuilder private var statusRow: some View {
        switch runState {
        case .idle:
            EmptyView()
        case .reading:
            HStack { ProgressView(); Text("Определяем сеть…").font(.caption).foregroundStyle(.secondary) }
        case .noMatch(let ssid):
            Text("Сеть «\(ssid)» без профиля.").font(.caption).foregroundStyle(.secondary)
        case .unavailable(let reason):
            Text(LocalizedStringKey(reason)).font(.caption).foregroundStyle(.orange)
        case .running(let ssid):
            HStack { ProgressView(); Text("Проверяем «\(ssid)»…").font(.caption).foregroundStyle(.secondary) }
        case .done(let ssid, let summary):
            VStack(alignment: .leading, spacing: 2) {
                Text("Сеть «\(ssid)»").font(.caption).foregroundStyle(.secondary)
                Text(summary).font(.caption)
            }
        }
    }

    private func profileRow(_ profile: NetworkProfile) -> some View {
        HStack {
            Image(systemName: profile.isEnabled ? "wifi" : "wifi.slash")
                .foregroundStyle(profile.isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.ssid.isEmpty ? "Без имени" : profile.ssid)
                Text("Проверок: \(profile.checkIDs.count)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func runForCurrentNetwork() async {
        runState = .reading
        let result = await CurrentNetwork.current()
        let ssid: String
        switch result {
        case .ssid(let name):
            ssid = name
        case .restricted(let reason), .unavailable(let reason):
            runState = .unavailable(reason: reason)
            return
        }

        guard let profile = store.profile(forSSID: ssid) else {
            runState = .noMatch(ssid: ssid)
            return
        }

        runState = .running(ssid: ssid)
        var restricted = 0
        for id in profile.checkIDs {
            guard let check = BlockingCheck(rawValue: id) else { continue }
            let target = profile.target.isEmpty ? check.defaultTarget : profile.target
            let finding = await check.run(target: target)
            if finding.verdict == .restricted { restricted += 1 }
            WebhookReporter.reportBlocking(check: id, target: target, finding: finding, eventPrefix: "profile")
        }
        let summary = restricted == 0
            ? "Ограничений не найдено (\(profile.checkIDs.count) проверок)."
            : "Найдено ограничений: \(restricted) из \(profile.checkIDs.count)."
        runState = .done(ssid: ssid, summary: summary)
    }
}

/// Create or edit a profile.
struct NetworkProfileEditor: View {
    @Environment(NetworkProfileStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NetworkProfile
    private let isNew: Bool

    init(profile: NetworkProfile) {
        _draft = State(initialValue: profile)
        isNew = profile.ssid.isEmpty && profile.checkIDs.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Сеть") {
                    TextField("Имя Wi-Fi (SSID)", text: $draft.ssid)
                        .autocorrectionDisabled()
                    Toggle("Профиль активен", isOn: $draft.isEnabled)
                }

                Section("Проверки") {
                    ForEach(BlockingCheck.allCases) { check in
                        Button {
                            toggle(check)
                        } label: {
                            HStack {
                                Image(systemName: draft.checkIDs.contains(check.rawValue) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(draft.checkIDs.contains(check.rawValue) ? Color.accentColor : .secondary)
                                Text(LocalizedStringKey(check.title))
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Цель (необязательно)") {
                    TextField("Домен по умолчанию у каждой проверки", text: $draft.target)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }
            }
            .navigationTitle(isNew ? "Новый профиль" : "Профиль")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(draft.ssid.trimmingCharacters(in: .whitespaces).isEmpty || draft.checkIDs.isEmpty)
                }
            }
        }
    }

    private func toggle(_ check: BlockingCheck) {
        if let index = draft.checkIDs.firstIndex(of: check.rawValue) {
            draft.checkIDs.remove(at: index)
        } else {
            draft.checkIDs.append(check.rawValue)
        }
    }

    private func save() {
        draft.ssid = draft.ssid.trimmingCharacters(in: .whitespaces)
        if store.profiles.contains(where: { $0.id == draft.id }) {
            store.update(draft)
        } else {
            store.add(draft)
        }
        dismiss()
    }
}
