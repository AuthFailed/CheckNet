import SwiftUI
import NetworkKit

@MainActor
@Observable
final class DNSLookupModel {
    var host = "example.com"
    var recordType: DNSRecordType = .a
    var resolver: DNSResolverInfo = DNSResolverInfo.presets[0]
    var dnssec = false

    private(set) var isRunning = false
    private(set) var result: DNSResult?
    private(set) var errorMessage: String?

    private let client = DNSClient()

    func run() async {
        let name = host.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isRunning = true
        errorMessage = nil
        result = nil
        do {
            result = try await client.query(
                name: name, type: recordType, resolver: resolver.address,
                options: .init(timeout: 4, dnssec: dnssec)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isRunning = false
    }
}

struct DNSLookupView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var model = DNSLookupModel()

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $model.host, placeholder: "Домен", icon: "magnifyingglass",
                         disabled: model.isRunning, savedHostTool: .dns) {
                Task { await model.run() }
            }

            controlsCard

            if let error = model.errorMessage {
                ErrorBanner(message: error)
            } else if let result = model.result {
                resultView(result)
            } else if model.isRunning {
                ProgressView().padding(.top, 40)
            }
        } bottom: {
            RunButton(title: "Запросить", running: model.isRunning,
                      disabled: model.host.trimmingCharacters(in: .whitespaces).isEmpty) {
                if model.isRunning { return }
                Task { await model.run() }
            }
        }
        .animation(.snappy, value: model.result)
        .navigationTitle("DNS")
        .toolTitleDisplayMode()
        .onAppear {
            if let presetHost { model.host = presetHost }
            if autostart { Task { await model.run() } }
        }
    }

    private var controlsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Тип записи").foregroundStyle(.secondary)
                Spacer()
                Picker("Тип записи", selection: $model.recordType) {
                    ForEach(DNSRecordType.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider().padding(.leading, 14)
            HStack {
                Text("Резолвер").foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $model.resolver) {
                    ForEach(DNSResolverInfo.presets) { r in
                        Text("\(r.name) · \(r.address)").tag(r)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider().padding(.leading, 14)
            Toggle("DNSSEC (DO)", isOn: $model.dnssec)
                .padding(.horizontal, 14).padding(.vertical, 6)
        }
        .card()
    }

    private func resultView(_ result: DNSResult) -> some View {
        VStack(spacing: 14) {
            statusCard(result)
            if !result.answers.isEmpty {
                recordsCard("Ответы", result.answers)
            } else {
                emptyAnswers
            }
            if !result.authorities.isEmpty {
                recordsCard("Authority", result.authorities)
            }
        }
    }

    private func statusCard(_ result: DNSResult) -> some View {
        let ok = result.responseCode == .noError
        return HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.responseCode.label).font(.headline)
                Text("\(result.answers.count) записей · \(String(format: "%.0f", result.latencyMillis)) мс")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if result.authenticated {
                Label("DNSSEC", systemImage: "lock.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.green.opacity(0.12), in: Capsule())
            }
        }
        .padding(14)
        .card()
    }

    private func recordsCard(_ title: String, _ records: [DNSRecord]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: title)
            VStack(spacing: 0) {
                ForEach(Array(records.enumerated()), id: \.offset) { idx, record in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(record.type?.label ?? "\(record.rawType)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                            Spacer()
                            Text("TTL \(record.ttl)").font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(record.value)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    if idx < records.count - 1 { Divider().padding(.leading, 14) }
                }
            }
            .card()
        }
    }

    private var emptyAnswers: some View {
        Text("Записей не найдено")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
    }
}

/// Reusable inline error banner.
struct ErrorBanner: View {
    let message: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(LocalizedStringKey(message)).font(.callout).foregroundStyle(.primary)
            Spacer()
        }
        .padding(14)
        .card()
    }
}
