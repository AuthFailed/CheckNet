import SwiftUI
import NetworkKit

/// Incy deep-link: decode `incy://crypt1/…` into a subscription URL and generate
/// such a link (+ QR) from your own URL — so you can hand users a link instead of
/// a "bare" address (issue #78).
struct IncyLinkView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case decode, encode
        var id: String { rawValue }
        var title: LocalizedStringKey { self == .decode ? "Разобрать" : "Собрать" }
    }

    @State private var mode: Mode = .decode
    // decode
    @State private var link = ""
    @State private var decoded: IncyLink.Decoded?
    @State private var decodeError: String?
    // encode
    @State private var url = ""
    @State private var name = ""
    @State private var built: String?
    @State private var encodeError: String?

    var body: some View {
        Form {
            Section {
                Picker("Режим", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if mode == .decode { decodeContent } else { encodeContent }
        }
        .navigationTitle("Incy-ссылка")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            InfoButton(title: VPNTool.incyLink.title,
                       systemImage: VPNTool.incyLink.systemImage,
                       message: VPNTool.incyLink.info)
        }
    }

    // MARK: - Decode

    @ViewBuilder private var decodeContent: some View {
        Section {
            TextField("incy://crypt1/…", text: $link, axis: .vertical)
                .lineLimit(2...5)
                .font(.callout.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            HStack {
                Button { if let s = clipboard() { link = s } } label: {
                    Label("Вставить", systemImage: "doc.on.clipboard")
                }
                Spacer()
                Button { runDecode() } label: { Label("Разобрать", systemImage: "arrow.right.circle.fill") }
                    .buttonStyle(.borderedProminent)
                    .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } footer: {
            if let decodeError {
                Label(LocalizedStringKey(decodeError), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }

        if let decoded {
            Section("Подписка") {
                if let n = decoded.name { InfoRow(label: "Имя", value: n) }
                Text(decoded.url).font(.callout.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { copy(decoded.url) } label: { Label("Скопировать URL", systemImage: "doc.on.doc") }
            }
        }
    }

    private func runDecode() {
        decodeError = nil
        do { decoded = try IncyLink.decode(link.trimmingCharacters(in: .whitespacesAndNewlines)) }
        catch { decoded = nil; decodeError = decodeMessage(error) }
    }

    private func decodeMessage(_ error: Error) -> String {
        switch error as? IncyLink.LinkError {
        case .notAnIncyLink: "Это не ссылка incy://crypt1/…"
        case .invalidPayload: "Повреждённый payload"
        case .authenticationFailed: "Не прошла проверка подлинности"
        case .badJSON: "Внутри нет URL подписки"
        case .emptyURL, .none: "Не удалось разобрать ссылку"
        }
    }

    // MARK: - Encode

    @ViewBuilder private var encodeContent: some View {
        Section {
            TextField("URL подписки (https://…)", text: $url)
                .font(.callout.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            TextField("Название (необязательно)", text: $name)
            Button { runEncode() } label: { Label("Создать ссылку", systemImage: "link.badge.plus") }
                .buttonStyle(.borderedProminent)
                .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } footer: {
            if let encodeError {
                Label(LocalizedStringKey(encodeError), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }

        if let built {
            Section("Ссылка") {
                Text(built).font(.callout.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { copy(built) } label: { Label("Скопировать", systemImage: "doc.on.doc") }
            }
            Section {
                QRCodeView(text: built)
                    .frame(maxWidth: 260)
                    .frame(maxWidth: .infinity)
            } footer: {
                Text("Откройте ссылку или отсканируйте QR на устройстве с установленным INCY.")
            }
        }
    }

    private func runEncode() {
        encodeError = nil
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do { built = try IncyLink.encode(url: u, name: n.isEmpty ? nil : n) }
        catch { built = nil; encodeError = "Не удалось создать ссылку" }
    }

    // MARK: - Clipboard

    private func clipboard() -> String? {
        #if os(iOS)
        return UIPasteboard.general.string
        #elseif os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #else
        return nil
        #endif
    }

    private func copy(_ s: String) {
        #if os(iOS)
        UIPasteboard.general.string = s
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        #endif
    }
}
