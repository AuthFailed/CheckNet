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
                Toggle("Отправлять вебхуки", isOn: $settings.isEnabled)
            } footer: {
                Text("Результаты проверок будут отправляться на указанный адрес. Это раскрытие данных: имена хостов, вердикты и задержки покинут устройство.")
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
                Text("Адрес")
            } footer: {
                Text("Только https. Исключение — localhost, чтобы можно было проверить приём локально.")
            }

            Section {
                HStack {
                    SecureField("Необязательно", text: $settings.secret)
                    if settings.secret.isEmpty {
                        Button {
                            settings.generateSecret()
                        } label: {
                            Image(systemName: "wand.and.stars").accessibilityLabel("Сгенерировать секрет")
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Button(role: .destructive) {
                            settings.clearSecret()
                        } label: {
                            Image(systemName: "xmark.circle.fill").accessibilityLabel("Очистить секрет")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Секрет для подписи")
            } footer: {
                Text("Если задан, каждый запрос подписывается: заголовок X-CheckNet-Signature содержит sha256=HMAC-SHA256 от тела. Получатель может убедиться, что запрос пришёл именно от этого устройства.")
            }

            Section {
                Picker("События", selection: $settings.trigger) {
                    ForEach(WebhookTrigger.allCases) { Text(LocalizedStringKey($0.label)).tag($0) }
                }
                Picker("Формат", selection: $settings.format) {
                    ForEach(WebhookFormat.allCases) { Text(LocalizedStringKey($0.label)).tag($0) }
                }
                Toggle("Live-режим", isOn: $settings.liveMode)
            } header: {
                Text("Что отправлять")
            } footer: {
                Text("В live-режиме промежуточные результаты теста отправляются по ходу выполнения (не чаще раза в секунду), а не только финальный итог.")
            }

            Section {
                ForEach(WebhookCatalog.schemas, id: \.toolKey) { schema in
                    NavigationLink {
                        WebhookFieldsView(schema: schema)
                    } label: {
                        LabeledContent(schema.toolLabel,
                                       value: "\(settings.selectedFields(forTool: schema.toolKey).count) полей")
                    }
                }
            } header: {
                Text("Данные по инструментам")
            } footer: {
                Text("По умолчанию отправляются все данные, которые умеет отдавать инструмент. Здесь можно отключить ненужные поля.")
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
                        Label("Отправить тестовое событие", systemImage: "paperplane")
                        if isSendingTest { Spacer(); ProgressView() }
                    }
                }
                .disabled(isSendingTest || settings.validatedURL == nil)

                if let status = settings.lastStatus {
                    Text(LocalizedStringKey(status)).font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Формат payload и заголовков описан в docs/webhooks.md репозитория.")
            }
        }
        .navigationTitle("Вебхуки")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
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
                        Text(field.label)
                    } footer: {
                        Text("Промежуточные результаты. Можно отключить весь список или отдельные поля в каждом элементе.")
                    }
                } else {
                    fieldToggle(field.key, field.label)
                }
            }

            Section {
                Button("Сбросить к значениям по умолчанию") {
                    settings.resetFields(forTool: schema.toolKey)
                }
            }
        }
        .navigationTitle(schema.toolLabel)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func fieldToggle(_ path: String, _ label: String) -> some View {
        Toggle(LocalizedStringKey(label), isOn: Binding(
            get: { settings.isFieldSelected(toolKey: schema.toolKey, path: path) },
            set: { settings.setField(toolKey: schema.toolKey, path: path, on: $0) }
        ))
    }
}
