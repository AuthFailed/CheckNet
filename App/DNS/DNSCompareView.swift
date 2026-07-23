import SwiftUI
import NetworkKit

struct DNSCompareView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var host = "wikipedia.org"
    @State private var recordType: DNSRecordType = .a
    @State private var run = ToolRunModel<[DNSResolverComparisonRow]>()

    private var rows: [DNSResolverComparisonRow] { run.value ?? [] }

    private func start() {
        let name = host.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !run.isRunning else { return }
        let type = recordType
        run.start { await DNSClient().compareResolvers(name: name, type: type, resolvers: DNSResolverInfo.presets) }
    }

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $host, placeholder: "Домен", icon: "arrow.left.arrow.right",
                         disabled: run.isRunning, savedHostTool: .dnsCompare) { start() }
            HStack {
                Text("Тип записи").foregroundStyle(.secondary)
                Spacer()
                Picker("Тип записи", selection: $recordType) {
                    ForEach([DNSRecordType.a, .aaaa, .mx, .txt, .ns], id: \.self) { Text($0.label).tag($0) }
                }.labelsHidden()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .card()
        } content: {
            ForEach(rows) { row in
                resolverCard(row)
            }
            if run.isRunning && rows.isEmpty {
                ProgressView().padding(.top, 40)
            } else if rows.isEmpty {
                ToolIdleHint(
                    icon: "arrow.left.arrow.right",
                    title: "Готово к сравнению",
                    message: "Спросим один домен у нескольких публичных резолверов сразу — расхождение в ответах видно построчно.",
                    example: "wikipedia.org",
                    current: host
                ) { host = "wikipedia.org" }
            }
        } bottom: {
            RunButton(title: "Сравнить", running: run.isRunning,
                      disabled: host.trimmingCharacters(in: .whitespaces).isEmpty) {
                start()
            }
        }
        .animation(.snappy, value: rows.count)
        .navigationTitle("Сравнение резолверов")
        .toolTitleDisplayMode()
        .onAppear {
            if let presetHost { host = presetHost }
            if autostart { start() }
        }
    }

    private func resolverCard(_ row: DNSResolverComparisonRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(row.resolver.name).font(.headline)
                Text(row.resolver.address).font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                if let r = row.result {
                    Text("\(String(format: "%.0f", r.latencyMillis)) мс")
                        .font(.caption.monospaced())
                        .foregroundStyle(.blue)
                }
            }
            if let error = row.error {
                Text(error).font(.caption).foregroundStyle(.orange)
            } else if let r = row.result {
                let values = r.answers.filter { $0.rawType == r.queryType.rawValue }.map(\.value)
                if values.isEmpty {
                    Text(r.responseCode.label).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                        Text(v).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
    }
}

// MARK: - Tamper detection

struct DNSTamperView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var host = "example.com"
    @State private var run = ToolRunModel<DNSTamperReport>()
    /// The finding bullet grows with text size instead of sitting at 6 pt.
    @ScaledMetric(relativeTo: .callout) private var bulletSize: CGFloat = 7

    private func start() {
        let name = host.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !run.isRunning else { return }
        run.start { await DNSClient().detectTampering(name: name) }
    }

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $host, placeholder: "Домен", icon: "exclamationmark.shield",
                         disabled: run.isRunning, savedHostTool: .dnsTamper) { start() }
            if let report = run.value {
                verdictCard(report)
            }
        } content: {
            if let report = run.value {
                findingsCard(report)
            } else if run.isRunning {
                ProgressView().padding(.top, 40)
            }
        } bottom: {
            RunButton(title: "Проверить", running: run.isRunning,
                      disabled: host.trimmingCharacters(in: .whitespaces).isEmpty) {
                start()
            }
        }
        .animation(.snappy, value: run.value?.suspicious)
        .navigationTitle("Детект DNS-подмены")
        .toolTitleDisplayMode()
        .onAppear {
            if let presetHost { host = presetHost }
            if autostart { start() }
        }
    }

    private func verdictCard(_ report: DNSTamperReport) -> some View {
        HStack(spacing: 12) {
            Image(systemName: report.suspicious ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                .font(.title)
                .foregroundStyle(report.suspicious ? .orange : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(report.suspicious ? LocalizedStringKey("Есть признаки подмены") : LocalizedStringKey("Подмены не обнаружено"))
                    .font(.title3.weight(.bold))
                Text("Сравнено \(report.rows.count) резолверов")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16).card()
    }

    private func findingsCard(_ report: DNSTamperReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(report.findings.enumerated()), id: \.offset) { idx, finding in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "circle.fill").font(.system(size: bulletSize)).foregroundStyle(.secondary)
                        .padding(.top, 6).accessibilityHidden(true)
                    Text(LocalizedStringKey(finding)).font(.callout)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                if idx < report.findings.count - 1 { Divider().padding(.leading, 34) }
            }
        }
        .card()
    }
}
