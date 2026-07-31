import SwiftUI
import NetworkKit

/// Configure where check results are sent.
struct WebhookSettingsView: View {
    @Environment(WebhookSettings.self) private var settings
    @State private var isSendingTest = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Send webhooks", isOn: $settings.isEnabled)
            } footer: {
                Text("Check results will be sent to the address you enter. This discloses data: host names, verdicts and latencies leave your device.")
            }

            Section {
                TextField("https://example.com/hook", text: $settings.urlString)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                if let message = settings.validationMessage {
                    Text(LocalizedStringKey(message)).font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text("Address")
            } footer: {
                Text("HTTPS only. The exception is localhost, so you can test receiving locally.")
            }

            Section {
                HStack {
                    SecureField("Optional", text: $settings.secret)
                    if settings.secret.isEmpty {
                        Button {
                            settings.generateSecret()
                        } label: {
                            Image(systemName: "wand.and.stars").accessibilityLabel("Generate secret")
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Button(role: .destructive) {
                            settings.clearSecret()
                        } label: {
                            Image(systemName: "xmark.circle.fill").accessibilityLabel("Clear secret")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Signing secret")
            } footer: {
                Text("If set, every request is signed: the X-CheckNet-Signature header contains sha256=HMAC-SHA256 of the body. The recipient can verify that the request really came from this device.")
            }

            Section {
                Picker("Events", selection: $settings.trigger) {
                    ForEach(WebhookTrigger.allCases) { Text(LocalizedStringKey($0.label)).tag($0) }
                }
                Picker("Format", selection: $settings.format) {
                    ForEach(WebhookFormat.allCases) { Text(LocalizedStringKey($0.label)).tag($0) }
                }
                Toggle("Live mode", isOn: $settings.liveMode)
            } header: {
                Text("What to send")
            } footer: {
                Text("In live mode, interim results are sent while the test runs (at most once per second), not just the final summary.")
            }

            Section {
                ForEach(WebhookCatalog.schemas, id: \.toolKey) { schema in
                    NavigationLink {
                        WebhookFieldsView(schema: schema)
                    } label: {
                        LabeledContent(schema.toolLabel,
                                       value: "\(settings.selectedFields(forTool: schema.toolKey).count) fields")
                    }
                }
            } header: {
                Text("Data per tool")
            } footer: {
                Text("By default, every field a tool can report is sent. Here you can turn off the ones you don’t need.")
            }

            Section {
                Button {
                    isSendingTest = true
                    Task {
                        await settings.sendTestEvent()
                        isSendingTest = false
                    }
                } label: {
                    HStack {
                        Label("Send test event", systemImage: "paperplane")
                        if isSendingTest { Spacer(); ProgressView() }
                    }
                }
                .disabled(isSendingTest || settings.validatedURL == nil)

                if let status = settings.lastStatus {
                    Text(LocalizedStringKey(status)).font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text("The payload and header format is documented in docs/webhooks.md in the repository.")
            }
        }
        .navigationTitle("Webhooks")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
    }
}

/// Toggle which of a tool's fields (and intermediate sub-fields) are sent.
struct WebhookFieldsView: View {
    @Environment(WebhookSettings.self) private var settings
    let schema: WebhookSchema

    var body: some View {
        Form {
            ForEach(schema.fields) { field in
                if field.isList {
                    Section {
                        fieldToggle(field.key, field.label)
                        // Sub-fields are only meaningful while the list is on.
                        if settings.isFieldSelected(toolKey: schema.toolKey, path: field.key) {
                            ForEach(field.children) { child in
                                fieldToggle("\(field.key).\(child.key)", child.label)
                                    .padding(.leading, 12)
                            }
                        }
                    } header: {
                        Text(LocalizedStringKey(field.label))
                    } footer: {
                        Text("Interim results. You can turn off the whole list or individual fields in each entry.")
                    }
                } else {
                    fieldToggle(field.key, field.label)
                }
            }

            Section {
                Button("Reset to defaults") {
                    settings.resetFields(forTool: schema.toolKey)
                }
            }
        }
        .navigationTitle(LocalizedStringKey(schema.toolLabel))
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
    }

    private func fieldToggle(_ path: String, _ label: String) -> some View {
        Toggle(LocalizedStringKey(label), isOn: Binding(
            get: { settings.isFieldSelected(toolKey: schema.toolKey, path: path) },
            set: { settings.setField(toolKey: schema.toolKey, path: path, on: $0) }
        ))
    }
}
