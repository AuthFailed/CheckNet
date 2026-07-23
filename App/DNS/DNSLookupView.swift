import SwiftUI
import NetworkKit

struct DNSLookupView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var host = "example.com"
    @State private var recordType: DNSRecordType = .a
    @State private var resolver: DNSResolverInfo = DNSResolverInfo.presets[0]
    @State private var dnssec = false
    @State private var run = ToolRunModel<DNSResult>()
    @Environment(AppSettings.self) private var settings

    private func start() {
        let name = host.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !run.isRunning else { return }
        let type = recordType, address = resolver.address, dnssec = dnssec
        run.activity = settings.liveActivitiesEnabled ? .init(
            kind: .lookup, title: name, subtitle: "DNS",
            content: { LookupActivityContent.view($0, running: name) { r in
                ("\(r.answers.count) записей", r.answers.first?.value ?? "нет ответа") } }
        ) : nil
        run.start {
            try await DNSClient().query(
                name: name, type: type, resolver: address,
                options: .init(timeout: 4, dnssec: dnssec)
            )
        }
    }

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $host, placeholder: "Домен", icon: "magnifyingglass",
                         disabled: run.isRunning, savedHostTool: .dns) {
                start()
            }

            controlsCard

            if let error = run.errorMessage {
                ErrorCard(message: error) { start() }
            } else if let result = run.value {
                statusCard(result)
            }
        } content: {
            if run.errorMessage == nil {
                if let result = run.value {
                    recordModules(result)
                } else if run.isRunning {
                    ProgressView().padding(.top, 40)
                } else {
                    ToolIdleHint(
                        icon: "magnifyingglass",
                        title: "Готово к запросу",
                        message: "Спросим выбранный резолвер о записях домена и покажем ответ целиком.",
                        example: "example.com",
                        current: host
                    ) { host = "example.com" }
                }
            }
        } bottom: {
            RunButton(title: "Запросить", running: run.isRunning,
                      disabled: host.trimmingCharacters(in: .whitespaces).isEmpty) {
                start()
            }
        }
        .animation(.snappy, value: run.value)
        // A check runs for seconds; people put the phone down while it does.
        .haptic(.success, trigger: run.isRunning) { !$0 && run.errorMessage == nil }
        .haptic(.failure, trigger: run.isRunning) { !$0 && run.errorMessage != nil }
        .navigationTitle("DNS")
        .toolTitleDisplayMode()
        .onAppear {
            if let presetHost { host = presetHost }
            if autostart { start() }
        }
    }

    private var controlsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Тип записи").foregroundStyle(.secondary)
                Spacer()
                Picker("Тип записи", selection: $recordType) {
                    ForEach(DNSRecordType.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider().padding(.leading, 14)
            HStack {
                Text("Резолвер").foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $resolver) {
                    ForEach(DNSResolverInfo.presets) { r in
                        Text("\(r.name) · \(r.address)").tag(r)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider().padding(.leading, 14)
            Toggle("DNSSEC (DO)", isOn: $dnssec)
                .padding(.horizontal, 14).padding(.vertical, 6)
        }
        .card()
    }

    /// Siblings, not a VStack: on a wide window the record lists are separate
    /// grid modules.
    @ViewBuilder
    private func recordModules(_ result: DNSResult) -> some View {
        if !result.answers.isEmpty {
            recordsCard("Ответы", result.answers)
        } else {
            emptyAnswers
        }
        if !result.authorities.isEmpty {
            recordsCard("Authority", result.authorities)
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
