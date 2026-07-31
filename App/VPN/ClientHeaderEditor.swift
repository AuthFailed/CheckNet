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
                            Label("Fetch versions from GitHub", systemImage: "arrow.down.circle")
                            Spacer()
                            if model.loadingVersions { ProgressView() }
                        }
                    }
                    .disabled(model.loadingVersions)
                    if let note = model.versionsNote {
                        Text(LocalizedStringKey(note)).font(.caption).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("App and version build the User-Agent \"App/Version\". Versions from GitHub are available for open-source clients; the rest are entered manually.")
                }

                Section {
                    Toggle("Send HWID", isOn: $model.sendHWID)
                        .onChange(of: model.sendHWID) { model.saveHWID() }
                    if model.sendHWID {
                        HStack(spacing: 8) {
                            TextField("Device HWID", text: $model.hwid)
                                .font(.system(.body, design: .monospaced))
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                                .onChange(of: model.hwid) { model.saveHWID() }
                            Button { model.generateHWID() } label: {
                                Image(systemName: "wand.and.stars")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Generate HWID")
                        }
                    }
                } header: {
                    Text("HWID")
                } footer: {
                    Text("Sent as the X-HWID header — some panels bind the subscription to a device and limit the number of HWIDs. Turn off to not send HWID at all.")
                }

                Section("Clients") {
                    ForEach($model.clients) { $client in
                        clientRow($client)
                    }
                    .onDelete { model.remove(atOffsets: $0) }
                }

                Section {
                    Button { model.addClient() } label: {
                        Label("Add client", systemImage: "plus")
                    }
                    Button(role: .destructive) { model.resetClients() } label: {
                        Label("Reset to defaults", systemImage: "arrow.uturn.backward")
                    }
                }
            }
            .navigationTitle("Clients and versions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { model.saveClients(); dismiss() }
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
                    .accessibilityLabel("Enable \(client.wrappedValue.app)")
                TextField("App", text: client.app)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            HStack(spacing: 8) {
                TextField("Version", text: client.version)
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
                Text("First \"Fetch versions from GitHub\"")
            } else {
                ForEach(versions, id: \.self) { v in
                    Button(v) { client.version.wrappedValue = v; model.saveClients() }
                }
            }
        } label: {
            Image(systemName: "chevron.down.circle")
                .foregroundStyle(.tint)
        }
        .accessibilityLabel("Versions from GitHub")
    }
}
