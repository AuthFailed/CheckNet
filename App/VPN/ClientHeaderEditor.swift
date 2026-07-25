import SwiftUI
import NetworkKit

/// Lets the operator tailor which clients the header test runs as: edit each
/// app name and version by hand (composing the `User-Agent`), pull real
/// versions from GitHub for open-source clients, toggle clients off, add a
/// custom one, or reset to the built-in set (#75).
struct ClientEditorView: View {
    @Bindable var model: ClientHeadersModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        Task { await model.loadVersionsFromGitHub() }
                    } label: {
                        HStack {
                            Label("Подтянуть версии с GitHub", systemImage: "arrow.down.circle")
                            Spacer()
                            if model.loadingVersions { ProgressView() }
                        }
                    }
                    .disabled(model.loadingVersions)
                    if let note = model.versionsNote {
                        Text(LocalizedStringKey(note)).font(.caption).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Приложение и версия собирают User-Agent «Приложение/Версия». Версии с GitHub доступны для клиентов с открытым исходным кодом; остальные вводятся вручную.")
                }

                Section("Клиенты") {
                    ForEach($model.clients) { $client in
                        clientRow($client)
                    }
                    .onDelete { model.remove(atOffsets: $0) }
                }

                Section {
                    Button { model.addClient() } label: {
                        Label("Добавить клиента", systemImage: "plus")
                    }
                    Button(role: .destructive) { model.resetClients() } label: {
                        Label("Сбросить к стандартным", systemImage: "arrow.uturn.backward")
                    }
                }
            }
            .navigationTitle("Клиенты и версии")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { model.saveClients(); dismiss() }
                }
            }
            .onChange(of: model.clients) { model.saveClients() }
        }
    }

    @ViewBuilder private func clientRow(_ client: Binding<EditableClient>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Toggle(isOn: client.enabled) { EmptyView() }
                    .labelsHidden()
                    .accessibilityLabel("Включить \(client.wrappedValue.app)")
                TextField("Приложение", text: client.app)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            HStack(spacing: 8) {
                TextField("Версия", text: client.version)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                if let repo = client.wrappedValue.repo {
                    versionMenu(client, repo: repo)
                }
            }
            Text(client.wrappedValue.userAgent.isEmpty ? "—" : client.wrappedValue.userAgent)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
        .opacity(client.wrappedValue.enabled ? 1 : 0.5)
    }

    @ViewBuilder private func versionMenu(_ client: Binding<EditableClient>, repo: String) -> some View {
        let versions = model.githubVersions[repo] ?? []
        Menu {
            if versions.isEmpty {
                Text("Сначала «Подтянуть версии с GitHub»")
            } else {
                ForEach(versions, id: \.self) { v in
                    Button(v) { client.version.wrappedValue = v; model.saveClients() }
                }
            }
        } label: {
            Image(systemName: "chevron.down.circle")
                .foregroundStyle(.tint)
        }
        .accessibilityLabel("Версии с GitHub")
    }
}
