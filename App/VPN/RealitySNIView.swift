import SwiftUI
import NetworkKit

/// Checks a domain's suitability as an SNI/dest for Reality (#70). We enter a domain,
/// the engine does a live TLS handshake and returns a verdict against the criteria
/// followed by the reference `XTLS/RealiTLScanner` and the REALITY README: TLS 1.3,
/// ALPN h2, a real certificate, X25519 support and no external
/// redirect. Diagnostics only — no circumvention here.
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
            HostInputBar(text: $host, placeholder: "Domain (e.g. www.microsoft.com)",
                         icon: "checkmark.shield", disabled: run.isRunning) {
                start()
            } trailing: {
                AnyView(
                    HStack(spacing: 2) {
                        Text(":").foregroundStyle(.secondary)
                        TextField("port", value: $port, format: .number)
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
                    title: "Let's check a domain for Reality",
                    message: "A TLS handshake shows whether the domain works as dest/SNI: TLS 1.3, HTTP/2, X25519, certificate and redirect.",
                    example: "www.microsoft.com",
                    current: host
                ) { host = "www.microsoft.com" }
            }
        } bottom: {
            RunButton(title: "Check", running: run.isRunning,
                      disabled: host.trimmingCharacters(in: .whitespaces).isEmpty) {
                start()
            }
        }
        .animation(.snappy, value: run.value)
        .haptic(.success, trigger: run.isRunning) { !$0 && run.value?.verdict != .fail }
        .haptic(.failure, trigger: run.isRunning) { !$0 && run.value?.verdict == .fail }
        .navigationTitle("SNI for Reality")
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
                                Text("required")
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
            InfoRow(label: "IP address", value: report.resolvedIP, mono: true)
            Divider().padding(.leading, 14)
            InfoRow(label: "TLS", value: report.tlsVersion, mono: true)
            Divider().padding(.leading, 14)
            InfoRow(label: "ALPN", value: report.alpn ?? "—", mono: true)
            Divider().padding(.leading, 14)
            InfoRow(label: "X25519", value: report.supportsX25519 ? "supported" : "no")
            if !report.certSubject.isEmpty {
                Divider().padding(.leading, 14)
                InfoRow(label: "Certificate", value: report.certSubject)
                Divider().padding(.leading, 14)
                InfoRow(label: "Issuer", value: report.certIssuer)
            }
            if let days = report.certExpiryDays {
                Divider().padding(.leading, 14)
                InfoRow(label: "Certificate validity", value: "\(days) d",
                        valueColor: days < 21 ? .orange : .primary)
            }
            if let redirect = report.redirectLocation {
                Divider().padding(.leading, 14)
                InfoRow(label: "Redirect", value: redirect, valueColor: .orange)
            }
            Divider().padding(.leading, 14)
            InfoRow(label: "Handshake", value: "\(Int(report.handshakeMillis)) ms", mono: true)
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
        case .pass: "Domain suitable"
        case .warn: "Suitable with caveats"
        case .fail: "Domain not suitable"
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
        case .pass: "done"
        case .warn: "caveat"
        case .fail: "not done"
        }
    }
}
