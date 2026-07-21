import SwiftUI
import NetworkKit

@MainActor
@Observable
final class DNSCompareModel {
    var host = "wikipedia.org"
    var recordType: DNSRecordType = .a
    private(set) var isRunning = false
    private(set) var rows: [DNSResolverComparisonRow] = []

    func run() async {
        let name = host.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isRunning = true; rows = []
        rows = await DNSClient().compareResolvers(name: name, type: recordType, resolvers: DNSResolverInfo.presets)
        isRunning = false
    }
}

struct DNSCompareView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var model = DNSCompareModel()

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $model.host, placeholder: "Домен", icon: "arrow.left.arrow.right",
                         disabled: model.isRunning, savedHostTool: .dnsCompare) { Task { await model.run() } }
            HStack {
                Text("Тип записи").foregroundStyle(.secondary)
                Spacer()
                Picker("Тип записи", selection: $model.recordType) {
                    ForEach([DNSRecordType.a, .aaaa, .mx, .txt, .ns], id: \.self) { Text($0.label).tag($0) }
                }.labelsHidden()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .card()

            ForEach(model.rows) { row in
                resolverCard(row)
            }
            if model.isRunning && model.rows.isEmpty {
                ProgressView().padding(.top, 40)
            }
        } bottom: {
            RunButton(title: "Сравнить", running: model.isRunning,
                      disabled: model.host.trimmingCharacters(in: .whitespaces).isEmpty) {
                if model.isRunning { return }; Task { await model.run() }
            }
        }
        .animation(.snappy, value: model.rows.count)
        .navigationTitle("Сравнение резолверов")
        .toolTitleDisplayMode()
        .onAppear {
            if let presetHost { model.host = presetHost }
            if autostart { Task { await model.run() } }
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

@MainActor
@Observable
final class DNSTamperModel {
    var host = "example.com"
    private(set) var isRunning = false
    private(set) var report: DNSTamperReport?

    func run() async {
        let name = host.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isRunning = true; report = nil
        report = await DNSClient().detectTampering(name: name)
        isRunning = false
    }
}

struct DNSTamperView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var model = DNSTamperModel()

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $model.host, placeholder: "Домен", icon: "exclamationmark.shield",
                         disabled: model.isRunning, savedHostTool: .dnsTamper) { Task { await model.run() } }
            if let report = model.report {
                verdictCard(report)
                findingsCard(report)
            } else if model.isRunning {
                ProgressView().padding(.top, 40)
            }
        } bottom: {
            RunButton(title: "Проверить", running: model.isRunning,
                      disabled: model.host.trimmingCharacters(in: .whitespaces).isEmpty) {
                if model.isRunning { return }; Task { await model.run() }
            }
        }
        .animation(.snappy, value: model.report?.suspicious)
        .navigationTitle("Детект DNS-подмены")
        .toolTitleDisplayMode()
        .onAppear {
            if let presetHost { model.host = presetHost }
            if autostart { Task { await model.run() } }
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
                    Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.secondary)
                        .padding(.top, 6)
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
