import SwiftUI
import NetworkKit

/// Управление ядрами Xray для проверки «через прокси».
///
/// На macOS: скачивание выбранной версии с прогрессом, хранение нескольких
/// версий, удаление по одной или всех. На iOS ядро скачать/запустить нельзя
/// (App Store 2.5.2), поэтому показываем последнюю доступную версию и
/// объясняем, что проверка через прокси там использует нативную Reality-пробу.
struct XrayCoresEditor: View {
    @Environment(XrayCoreStore.self) private var store
    @State private var confirmDeleteAll = false

    var body: some View {
        List {
            if !XrayCoreStore.isSupported {
                Section {
                    Label("Ядро Xray доступно на Mac", systemImage: "desktopcomputer")
                        .font(.headline)
                    Text("iOS не разрешает скачивать и запускать стороннее ядро. Проверка «через прокси» на iPhone использует встроенную Reality-пробу без загрузки ядра.")
                        .font(.callout).foregroundStyle(.secondary)
                    if let latest = store.latestVersion {
                        InfoRow(label: "Последняя версия Xray", value: latest, mono: true)
                    }
                } footer: {
                    Text("На Mac здесь можно скачивать и хранить несколько версий ядра.")
                }
            }

            if !store.installed.isEmpty {
                Section("Установленные") {
                    ForEach(store.installed) { core in
                        HStack {
                            Label(core.version, systemImage: "shippingbox")
                            Spacer()
                            Text("\(core.sizeMB, specifier: "%.1f") МБ").foregroundStyle(.secondary).font(.caption)
                        }
                    }
                    .onDelete { idx in idx.map { store.installed[$0].version }.forEach(store.remove) }

                    Button(role: .destructive) { confirmDeleteAll = true } label: {
                        Label("Удалить все ядра", systemImage: "trash")
                    }
                }
            }

            if XrayCoreStore.isSupported {
                Section {
                    if let dl = store.active {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Загрузка \(dl.version)…").font(.callout)
                            ProgressView(value: dl.progress)
                        }
                    } else if store.loadingIndex {
                        HStack { ProgressView(); Text("Получаем список версий…").foregroundStyle(.secondary) }
                    } else if store.available.isEmpty {
                        Button { Task { await store.refreshIndex() } } label: {
                            Label("Загрузить список версий", systemImage: "arrow.down.circle")
                        }
                    } else {
                        ForEach(store.available) { release in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(release.version).font(.callout.weight(.medium))
                                    Text("\(release.asset.sizeMB, specifier: "%.1f") МБ\(release.prerelease ? " · pre-release" : "")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.isInstalled(release.version) {
                                    Label("Установлено", systemImage: "checkmark.circle.fill")
                                        .labelStyle(.iconOnly).foregroundStyle(.green)
                                } else {
                                    Button("Скачать") { Task { await store.install(release) } }
                                        .disabled(store.active != nil)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Доступные версии")
                } footer: {
                    if let e = store.installError {
                        Text(LocalizedStringKey(e)).foregroundStyle(.red)
                    } else {
                        Text("Скачивается официальная сборка Xray-core с GitHub, проверяется контрольная сумма.")
                    }
                }
            }
        }
        .navigationTitle("Ядро Xray")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        .task { if XrayCoreStore.isSupported && store.available.isEmpty { await store.refreshIndex() } }
        .confirmationDialog("Удалить все скачанные ядра?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Удалить все", role: .destructive) { store.removeAll() }
            Button("Отмена", role: .cancel) {}
        }
    }
}
