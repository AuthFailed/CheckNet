import SwiftUI
import NetworkKit

struct WhoisView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var query = "apple.com"
    @State private var run = ToolRunModel<WhoisResult>()
    @State private var showRaw = false

    private func start() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !run.isRunning else { return }
        run.start { try await WhoisClient().lookup(q) }
    }

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $query, placeholder: "Домен", icon: "doc.text.magnifyingglass",
                         disabled: run.isRunning, savedHostTool: .whois) { start() }
            if let error = run.errorMessage {
                ErrorCard(message: error) { start() }
            }
        } content: {
            if run.errorMessage == nil {
                if let result = run.value {
                    if !result.fields.isEmpty { fieldsCard(result) }
                    rawDisclosure(result)
                } else if run.isRunning {
                    ProgressView().padding(.top, 40)
                } else {
                    ToolIdleHint(
                        icon: "doc.text.magnifyingglass",
                        title: "Готово к запросу whois",
                        message: "Узнаем регистратора домена, даты регистрации и окончания, серверы имён.",
                        example: "apple.com",
                        current: query
                    ) { query = "apple.com" }
                }
            }
        } bottom: {
            RunButton(title: "Запросить", running: run.isRunning,
                      disabled: query.trimmingCharacters(in: .whitespaces).isEmpty) {
                start()
            }
        }
        .animation(.snappy, value: run.value)
        // A check runs for seconds; people put the phone down while it does.
        .haptic(.success, trigger: run.isRunning) { !$0 && run.errorMessage == nil }
        .haptic(.failure, trigger: run.isRunning) { !$0 && run.errorMessage != nil }
        .navigationTitle("Whois")
        .toolTitleDisplayMode()
        .onAppear {
            if let presetHost { query = presetHost }
            if autostart { start() }
        }
    }

    private func fieldsCard(_ result: WhoisResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: "Сервер: \(result.server)")
            VStack(spacing: 0) {
                ForEach(Array(result.fields.enumerated()), id: \.element.id) { idx, field in
                    InfoRow(label: field.key, value: field.value, mono: field.key.contains("NS"))
                    if idx < result.fields.count - 1 { Divider().padding(.leading, 14) }
                }
            }
            .card()
        }
    }

    private func rawDisclosure(_ result: WhoisResult) -> some View {
        DisclosureGroup(isExpanded: $showRaw) {
            Text(result.raw)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        } label: {
            Label("Полный ответ", systemImage: "doc.plaintext")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .card()
    }
}
