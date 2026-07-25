import SwiftUI
import NetworkKit

/// Проверка пригодности домена как SNI/dest для Reality (#70). Вводим домен,
/// движок делает живой TLS-хендшейк и отдаёт вердикт по критериям, которыми
/// руководствуется эталонный `XTLS/RealiTLScanner` и README REALITY: TLS 1.3,
/// ALPN h2, реальный сертификат, поддержка X25519 и отсутствие внешнего
/// редиректа. Только диагностика — обхода тут нет.
struct RealitySNIView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var host = "www.microsoft.com"
    @State private var port = 443
    @State private var run = ToolRunModel<RealitySNIReport>()

    private func start() {
        let target = host.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty, !run.isRunning else { return }
        let port = port
        run.start { await RealitySNICheck().run(host: target, port: port) }
    }

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $host, placeholder: "Домен (напр. www.microsoft.com)",
                         icon: "checkmark.shield", disabled: run.isRunning) {
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

            if let report = run.value {
                verdictCard(report)
            }
        } content: {
            if let report = run.value {
                criteriaCard(report)
                detailsCard(report)
            } else if run.isRunning {
                ProgressView().padding(.top, 40)
            } else {
                ToolIdleHint(
                    icon: "checkmark.shield",
                    title: "Проверим домен для Reality",
                    message: "Хендшейк по TLS покажет, годится ли домен как dest/SNI: TLS 1.3, HTTP/2, X25519, сертификат и редирект.",
                    example: "www.microsoft.com",
                    current: host
                ) { host = "www.microsoft.com" }
            }
        } bottom: {
            RunButton(title: "Проверить", running: run.isRunning,
                      disabled: host.trimmingCharacters(in: .whitespaces).isEmpty) {
                start()
            }
        }
        .animation(.snappy, value: run.value)
        .haptic(.success, trigger: run.isRunning) { !$0 && run.value?.verdict != .fail }
        .haptic(.failure, trigger: run.isRunning) { !$0 && run.value?.verdict == .fail }
        .navigationTitle("SNI для Reality")
        .toolTitleDisplayMode()
        .onAppear {
            if let presetHost { host = presetHost }
            if autostart { start() }
        }
    }

    // MARK: - Verdict

    private func verdictCard(_ report: RealitySNIReport) -> some View {
        HStack(spacing: 12) {
            Image(systemName: verdictIcon(report.verdict))
                .font(.title)
                .foregroundStyle(verdictColor(report.verdict))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(verdictTitle(report.verdict)))
                    .font(.headline)
                Text(LocalizedStringKey(report.summary))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
        .padding(14)
        .card()
    }

    // MARK: - Criteria

    private func criteriaCard(_ report: RealitySNIReport) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(report.criteria.enumerated()), id: \.element.id) { index, c in
                if index > 0 { Divider().padding(.leading, 44) }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: gradeIcon(c.grade))
                        .font(.title3)
                        .foregroundStyle(gradeColor(c.grade))
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(LocalizedStringKey(c.title)).font(.subheadline.weight(.medium))
                            if c.isRequired {
                                Text("обяз.")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(.secondary.opacity(0.14), in: Capsule())
                            }
                        }
                        Text(LocalizedStringKey(c.detail))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("\(LocalizedStringKey(c.title)), \(LocalizedStringKey(gradeLabel(c.grade)))"))
            }
        }
        .card()
    }

    // MARK: - Details

    private func detailsCard(_ report: RealitySNIReport) -> some View {
        VStack(spacing: 0) {
            InfoRow(label: "IP-адрес", value: report.resolvedIP, mono: true)
            Divider().padding(.leading, 14)
            InfoRow(label: "TLS", value: report.tlsVersion, mono: true)
            Divider().padding(.leading, 14)
            InfoRow(label: "ALPN", value: report.alpn ?? "—", mono: true)
            Divider().padding(.leading, 14)
            InfoRow(label: "X25519", value: report.supportsX25519 ? "поддерживается" : "нет")
            if !report.certSubject.isEmpty {
                Divider().padding(.leading, 14)
                InfoRow(label: "Сертификат", value: report.certSubject)
                Divider().padding(.leading, 14)
                InfoRow(label: "Издатель", value: report.certIssuer)
            }
            if let days = report.certExpiryDays {
                Divider().padding(.leading, 14)
                InfoRow(label: "Срок сертификата", value: "\(days) дн.",
                        valueColor: days < 21 ? .orange : .primary)
            }
            if let redirect = report.redirectLocation {
                Divider().padding(.leading, 14)
                InfoRow(label: "Редирект", value: redirect, valueColor: .orange)
            }
            Divider().padding(.leading, 14)
            InfoRow(label: "Рукопожатие", value: "\(Int(report.handshakeMillis)) мс", mono: true)
        }
        .card()
    }

    // MARK: - Grade styling

    private func verdictIcon(_ g: RealityCriterion.Grade) -> String {
        switch g {
        case .pass: "checkmark.seal.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .fail: "xmark.seal.fill"
        }
    }
    private func verdictColor(_ g: RealityCriterion.Grade) -> Color {
        switch g {
        case .pass: .green
        case .warn: .orange
        case .fail: .red
        }
    }
    private func verdictTitle(_ g: RealityCriterion.Grade) -> String {
        switch g {
        case .pass: "Домен подходит"
        case .warn: "Подходит с замечаниями"
        case .fail: "Домен не подходит"
        }
    }
    private func gradeIcon(_ g: RealityCriterion.Grade) -> String {
        switch g {
        case .pass: "checkmark.circle.fill"
        case .warn: "exclamationmark.circle.fill"
        case .fail: "xmark.circle.fill"
        }
    }
    private func gradeColor(_ g: RealityCriterion.Grade) -> Color {
        switch g {
        case .pass: .green
        case .warn: .orange
        case .fail: .red
        }
    }
    private func gradeLabel(_ g: RealityCriterion.Grade) -> String {
        switch g {
        case .pass: "выполнено"
        case .warn: "замечание"
        case .fail: "не выполнено"
        }
    }
}
