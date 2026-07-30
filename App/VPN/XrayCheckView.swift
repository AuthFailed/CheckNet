import SwiftUI
import NetworkKit

struct XrayCheckOutcome: Equatable {
    let proto: String
    let host: String
    let port: Int
    let latencyMillis: Double
    let httpStatus: Int?
    /// gstatic's `/generate_204` answers 204 when the tunnel actually works.
    var ok: Bool { httpStatus == 204 || (httpStatus.map { (200..<400).contains($0) } ?? false) }
}

@MainActor
@Observable
final class XrayCheckModel {
    var input = ""
    private(set) var coreVersion: String?
    private(set) var isRunning = false
    private(set) var result: XrayCheckOutcome?
    private(set) var errorMessage: String?
    private var task: Task<Void, Never>?

    func loadVersion() {
        coreVersion = try? XrayCore.version()
    }

    func start() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning else { return }
        guard let node = SubscriptionParser.parse(text).nodes.first else {
            errorMessage = "Не удалось разобрать ссылку или конфиг"
            return
        }
        result = nil; errorMessage = nil; isRunning = true
        task = Task {
            do {
                let probe = try await XrayProxyRunner.probeInProcess(node: node)
                result = XrayCheckOutcome(
                    proto: node.proto.rawValue, host: node.host, port: node.port,
                    latencyMillis: probe.latencyMillis, httpStatus: probe.httpStatus
                )
            } catch {
                errorMessage = (error as? XrayProxyRunner.RunError)?.message ?? error.localizedDescription
            }
            isRunning = false
        }
    }

    func stop() { task?.cancel(); task = nil; isRunning = false; XrayCore.stop() }
}

/// Доступность Xray-инбаунда (#71): вставляем ссылку `vless://` / `trojan://`
/// или конфиг, поднимаем ядро Xray **в процессе** (libXray) с локальным SOCKS и
/// пробным запросом через сервер до gstatic — подтверждаем, что инбаунд рабочий,
/// и называем причину при сбое. Диагностика своего сервера, не обход.
struct XrayCheckView: View {
    var autostart = false
    @State private var model = XrayCheckModel()

    var body: some View {
        ToolScaffold {
            VStack(alignment: .leading, spacing: 8) {
                Label("Ссылка узла или конфиг", systemImage: "bolt.horizontal.circle")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("vless:// · trojan:// · xray json", text: $model.input, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(.callout, design: .monospaced))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .disabled(model.isRunning)
            }
            .padding(14).card()

            if let error = model.errorMessage {
                ErrorCard(message: error) { model.start() }
            } else if let result = model.result {
                resultCard(result)
            }
        } content: {
            if model.result == nil, !model.isRunning, model.errorMessage == nil {
                ToolIdleHint(
                    icon: "bolt.horizontal.circle",
                    title: "Проверка своего инбаунда",
                    message: "Ядро Xray поднимется в приложении, подключится к вашему серверу и сделает пробный запрос — так проверяется, что VLESS/Trojan-инбаунд действительно работает.",
                    example: "",
                    current: model.input
                )
            } else if model.isRunning {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Поднимаем ядро и пробуем соединение…")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 40)
            }
        } bottom: {
            RunButton(title: "Проверить", running: model.isRunning,
                      disabled: model.input.trimmingCharacters(in: .whitespaces).isEmpty) {
                if model.isRunning { model.stop() } else { model.start() }
            }
        }
        .animation(.snappy, value: model.result)
        .haptic(.success, trigger: model.isRunning) { !$0 && model.result?.ok == true }
        .haptic(.failure, trigger: model.isRunning) { !$0 && (model.errorMessage != nil || model.result?.ok == false) }
        .navigationTitle("Доступность Xray")
        .toolTitleDisplayMode()
        .safeAreaInset(edge: .bottom) {
            if let v = model.coreVersion {
                Text("Ядро Xray \(v)")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 2)
            }
        }
        .onAppear {
            model.loadVersion()
            if autostart { model.start() }
        }
    }

    private func resultCard(_ r: XrayCheckOutcome) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: r.ok ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.title).foregroundStyle(r.ok ? .green : .red)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.ok ? LocalizedStringKey("Инбаунд работает") : LocalizedStringKey("Соединение не прошло"))
                        .font(.headline)
                    Text(r.ok ? "Запрос через сервер дошёл до gstatic." : "Ядро поднялось, но запрос не прошёл.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
            .padding(14)
            Divider().padding(.leading, 14)
            InfoRow(label: "Протокол", value: r.proto.uppercased(), mono: true)
            Divider().padding(.leading, 14)
            InfoRow(label: "Сервер", value: "\(r.host):\(r.port)", mono: true)
            Divider().padding(.leading, 14)
            InfoRow(label: "Задержка", value: "\(Int(r.latencyMillis)) мс", mono: true)
            Divider().padding(.leading, 14)
            InfoRow(label: "HTTP-ответ", value: r.httpStatus.map(String.init) ?? "—", mono: true)
        }
        .card()
    }
}
