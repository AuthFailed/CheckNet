import SwiftUI
import NetworkKit

@MainActor
@Observable
final class TLSInspectorModel {
    var host = "cloudflare.com"
    var port = 443
    private(set) var isRunning = false
    private(set) var info: TLSInfo?
    private(set) var errorMessage: String?

    private let inspector = TLSInspector()

    func run() async {
        let target = host.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }
        isRunning = true; errorMessage = nil; info = nil
        do {
            info = try await inspector.inspect(host: target, port: port)
        } catch {
            errorMessage = error.localizedDescription
        }
        isRunning = false
    }
}

struct TLSInspectorView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var model = TLSInspectorModel()

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $model.host, placeholder: "Хост (напр. example.com)",
                         icon: "lock.shield", disabled: model.isRunning,
                         savedHostTool: .tlsInspector) {
                Task { await model.run() }
            } trailing: {
                AnyView(
                    HStack(spacing: 2) {
                        Text(":").foregroundStyle(.secondary)
                        TextField("порт", value: $model.port, format: .number)
                            .frame(minWidth: 46)
                            .multilineTextAlignment(.leading)
                            .font(.system(.body, design: .monospaced))
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .disabled(model.isRunning)
                    }
                )
            }

            if let error = model.errorMessage {
                ErrorCard(message: error) { Task { await model.run() } }
            } else if let info = model.info {
                handshakeCard(info)
            }
        } content: {
            if model.errorMessage == nil {
                if let info = model.info {
                    ForEach(Array(info.certificates.enumerated()), id: \.offset) { idx, cert in
                        certCard(cert, index: idx, isLeaf: idx == 0)
                    }
                } else if model.isRunning {
                    ProgressView().padding(.top, 40)
                } else {
                    ToolIdleHint(
                        icon: "lock.shield",
                        title: "Готово к разбору TLS",
                        message: "Покажем цепочку сертификатов, сроки действия, версию TLS и шифр.",
                        example: "cloudflare.com",
                        current: model.host
                    ) { model.host = "cloudflare.com" }
                }
            }
        } bottom: {
            RunButton(title: "Проверить", running: model.isRunning,
                      disabled: model.host.trimmingCharacters(in: .whitespaces).isEmpty) {
                if model.isRunning { return }
                Task { await model.run() }
            }
        }
        .animation(.snappy, value: model.info)
        // A check runs for seconds; people put the phone down while it does.
        .haptic(.success, trigger: model.isRunning) { !$0 && model.errorMessage == nil }
        .haptic(.failure, trigger: model.isRunning) { !$0 && model.errorMessage != nil }
        .navigationTitle("TLS-инспектор")
        .toolTitleDisplayMode()
        .onAppear {
            if let presetHost { model.host = presetHost }
            if autostart { Task { await model.run() } }
        }
    }

    private func handshakeCard(_ info: TLSInfo) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: info.trustEvaluationPassed ? "checkmark.shield.fill" : "xmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(info.trustEvaluationPassed ? .green : .red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.trustEvaluationPassed ? LocalizedStringKey("Сертификат доверенный") : LocalizedStringKey("Доверие не подтверждено"))
                        .font(.headline)
                    Text("\(info.resolvedIP) · \(String(format: "%.0f", info.handshakeMillis)) мс")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            Divider().padding(.leading, 14)
            InfoRow(label: "Протокол", value: info.negotiatedProtocol, mono: true)
            Divider().padding(.leading, 14)
            InfoRow(label: "Шифр", value: info.cipherSuite, mono: true)
            Divider().padding(.leading, 14)
            InfoRow(label: "ALPN", value: info.alpn ?? "—", mono: true)
        }
        .card()
    }

    private func certCard(_ cert: TLSCertificate, index: Int, isLeaf: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                let certLabel: LocalizedStringKey = isLeaf ? "Сертификат сервера"
                    : (cert.isCA ? "CA · уровень \(index)" : "Промежуточный \(index)")
                Text(certLabel)
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                validityBadge(cert)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
            Divider().padding(.leading, 14)
            InfoRow(label: "Субъект", value: cert.subject)
            Divider().padding(.leading, 14)
            InfoRow(label: "Издатель", value: cert.issuer)
            if isLeaf, !cert.subjectAltNames.isEmpty {
                Divider().padding(.leading, 14)
                InfoRow(label: "Домены (SAN)", value: cert.subjectAltNames.joined(separator: ", "))
            }
            Divider().padding(.leading, 14)
            InfoRow(label: "Действует до", value: dateString(cert.notAfter), valueColor: cert.isExpired ? .red : .primary)
            Divider().padding(.leading, 14)
            InfoRow(label: "SHA-256", value: shortFingerprint(cert.sha256Fingerprint), mono: true)
        }
        .card()
    }

    private func validityBadge(_ cert: TLSCertificate) -> some View {
        Group {
            if cert.isExpired {
                badge("Истёк", .red)
            } else if cert.isNotYetValid {
                badge("Ещё не активен", .orange)
            } else if let days = cert.daysUntilExpiry {
                badge("\(days) дн.", days < 21 ? .orange : .green)
            } else {
                EmptyView()
            }
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(LocalizedStringKey(text))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func dateString(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: date)
    }

    private func shortFingerprint(_ fp: String) -> String {
        let parts = fp.split(separator: ":")
        guard parts.count > 12 else { return fp }
        return parts.prefix(12).joined(separator: ":") + "…"
    }
}
