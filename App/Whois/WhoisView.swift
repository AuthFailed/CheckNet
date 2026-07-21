import SwiftUI
import NetworkKit

@MainActor
@Observable
final class WhoisModel {
    var query = "apple.com"
    private(set) var isRunning = false
    private(set) var result: WhoisResult?
    private(set) var errorMessage: String?

    func run() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isRunning = true; errorMessage = nil; result = nil
        do { result = try await WhoisClient().lookup(q) }
        catch { errorMessage = error.localizedDescription }
        isRunning = false
    }
}

struct WhoisView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var model = WhoisModel()
    @State private var showRaw = false

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $model.query, placeholder: "Домен", icon: "doc.text.magnifyingglass",
                         disabled: model.isRunning, savedHostTool: .whois) { Task { await model.run() } }
            if let error = model.errorMessage {
                ErrorBanner(message: error)
            } else if let result = model.result {
                if !result.fields.isEmpty { fieldsCard(result) }
                rawDisclosure(result)
            } else if model.isRunning {
                ProgressView().padding(.top, 40)
            }
        } bottom: {
            RunButton(title: "Запросить", running: model.isRunning,
                      disabled: model.query.trimmingCharacters(in: .whitespaces).isEmpty) {
                if model.isRunning { return }; Task { await model.run() }
            }
        }
        .animation(.snappy, value: model.result)
        .navigationTitle("Whois")
        .toolTitleDisplayMode()
        .onAppear {
            if let presetHost { model.query = presetHost }
            if autostart { Task { await model.run() } }
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
                .font(.system(size: 11, design: .monospaced))
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
