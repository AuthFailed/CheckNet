import SwiftUI
import NetworkKit

/// Расшифровка `happ://crypt…`-ссылок в читаемый вид (обычно URL подписки или
/// конфиг). Всё считается на устройстве (issue #77).
struct HappDecryptView: View {
    @State private var input = ""
    @State private var result: String?
    @State private var error: String?

    private var preview: HappDecrypt.Preview? {
        HappDecrypt.inspect(input.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        Form {
            Section {
                TextField("happ://crypt…", text: $input, axis: .vertical)
                    .lineLimit(2...6)
                    .font(.callout.monospaced())
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                HStack {
                    Button {
                        if let s = clipboardString() { input = s; result = nil; error = nil }
                    } label: { Label("Вставить", systemImage: "doc.on.clipboard") }
                    Spacer()
                    Button { decrypt() } label: {
                        Label("Расшифровать", systemImage: "lock.open.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(preview == nil)
                }
            } footer: {
                if let error {
                    Label(LocalizedStringKey(error), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                } else if let preview {
                    Text("Формат: \(preview.name)")
                }
            }

            if let result {
                Section("Результат") {
                    Text(result)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        copyToClipboard(result)
                    } label: { Label("Скопировать", systemImage: "doc.on.doc") }
                }
            }
        }
        .navigationTitle("Happ Decrypt")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            InfoButton(title: VPNTool.happDecrypt.title,
                       systemImage: VPNTool.happDecrypt.systemImage,
                       message: VPNTool.happDecrypt.info)
        }
    }

    private func decrypt() {
        error = nil
        do {
            result = try HappDecrypt.decrypt(input.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            result = nil
            self.error = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        switch error as? HappDecrypt.DecryptError {
        case .notACryptLink: "Это не ссылка happ://crypt…"
        case .keysUnavailable: "Ключи расшифровки недоступны"
        case .unknownMarker: "Неизвестный ключ crypt5 — возможно, новый формат"
        case .rsaFailed: "Ошибка RSA — ссылка повреждена или чужой формат"
        case .authenticationFailed: "Не прошла проверка подлинности (crypt5)"
        case .badFormat, .none: "Не удалось расшифровать ссылку"
        }
    }

    private func clipboardString() -> String? {
        #if os(iOS)
        return UIPasteboard.general.string
        #elseif os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #else
        return nil
        #endif
    }

    private func copyToClipboard(_ s: String) {
        #if os(iOS)
        UIPasteboard.general.string = s
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        #endif
    }
}
