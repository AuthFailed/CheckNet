import SwiftUI
import NetworkKit

/// Decrypts `happ://crypt…` links into a readable form (usually a subscription
/// URL or a config). Everything runs on the device (issue #77).
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
                    } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                    Spacer()
                    Button { decrypt() } label: {
                        Label("Decrypt", systemImage: "lock.open.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(preview == nil)
                }
            } footer: {
                if let error {
                    Label(LocalizedStringKey(error), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                } else if let preview {
                    Text("Format: \(preview.name)")
                }
            }

            if let result {
                Section("Result") {
                    Text(result)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        copyToClipboard(result)
                    } label: { Label("Copy", systemImage: "doc.on.doc") }
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
        case .notACryptLink: "Not a happ://crypt… link"
        case .keysUnavailable: "Decryption keys unavailable"
        case .unknownMarker: "Unknown crypt5 key — possibly a new format"
        case .rsaFailed: "RSA error — the link is corrupted or a foreign format"
        case .authenticationFailed: "Authentication failed (crypt5)"
        case .badFormat, .none: "Couldn't decrypt the link"
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
