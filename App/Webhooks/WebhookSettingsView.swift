import SwiftUI

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
                SecureField("Необязательно", text: $settings.secret)
            } header: {
                Text("Секрет для подписи")
            } footer: {
                Text("Если задан, каждый запрос подписывается: заголовок X-CheckNet-Signature содержит sha256=HMAC-SHA256 от тела. Получатель может убедиться, что запрос пришёл именно от этого устройства.")
            }

            Section("Что отправлять") {
                Picker("События", selection: $settings.trigger) {
                    ForEach(WebhookTrigger.allCases) { Text(LocalizedStringKey($0.label)).tag($0) }
                }
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
