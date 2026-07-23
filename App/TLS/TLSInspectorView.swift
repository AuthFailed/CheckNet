import SwiftUI
import NetworkKit

struct TLSInspectorView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var host = "cloudflare.com"
    @State private var port = 443
    @State private var run = ToolRunModel<TLSInfo>()

    private func start() {
        let target = host.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty, !run.isRunning else { return }
        let port = port
        run.start { try await TLSInspector().inspect(host: target, port: port) }
    }

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $host, placeholder: "Хост (напр. example.com)",
                         icon: "lock.shield", disabled: run.isRunning,
                         savedHostTool: .tlsInspector) {
                start()
            } trailing: {
                AnyView(
                    HStack(spacing: 2) {
                        Text(":").foregroundStyle(.secondary)
                        TextField("порт", value: $port, format: .number)
                            .frame(minWidth: 46)
                            .multilineTextAlignment(.leading)
                            .font(.system(.body, design: .monospaced))
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .disabled(run.isRunning)
                    }
                )
            }

            if let error = run.errorMessage {
                ErrorCard(message: error) { start() }
            } else if let info = run.value {
                handshakeCard(info)
            }
        } content: {
            if run.errorMessage == nil {
                if let info = run.value {
                    ForEach(Array(info.certificates.enumerated()), id: \.offset) { idx, cert in
                        certCard(cert, index: idx, isLeaf: idx == 0)
                    }
                } else if run.isRunning {
                    ProgressView().padding(.top, 40)
                } else {
                    ToolIdleHint(
                        icon: "lock.shield",
                        title: "Готово к разбору TLS",
                        message: "Покажем цепочку сертификатов, сроки действия, версию TLS и шифр.",
                        example: "cloudflare.com",
                        current: host
                    ) { host = "cloudflare.com" }
                }
            }
        } bottom: {
            RunButton(title: "Проверить", running: run.isRunning,
                      disabled: host.trimmingCharacters(in: .whitespaces).isEmpty) {
                start()
            }
        }
        .animation(.snappy, value: run.value)
        // A check runs for seconds; people put the phone down while it does.
        .haptic(.success, trigger: run.isRunning) { !$0 && run.errorMessage == nil }
        .haptic(.failure, trigger: run.isRunning) { !$0 && run.errorMessage != nil }
        .navigationTitle("TLS-инспектор")
        .toolTitleDisplayMode()
        .onAppear {
            if let presetHost { host = presetHost }
            if autostart { start() }
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
