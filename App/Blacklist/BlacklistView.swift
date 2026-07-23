import SwiftUI
import NetworkKit

struct BlacklistView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var ip = "8.8.8.8"
    @State private var run = ToolRunModel<BlacklistReport>()
    @Environment(AppSettings.self) private var settings

    private func start() {
        let target = ip.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty, !run.isRunning else { return }
        run.activity = settings.liveActivitiesEnabled ? .init(
            kind: .lookup, title: target, subtitle: "Чёрные списки",
            content: { LookupActivityContent.view($0, running: target,
                status: { $0.listedCount > 0 ? .down : .ok }) { r in
                (r.listedCount > 0 ? "В списках: \(r.listedCount)" : "Чисто",
                 "проверено \(r.checkedCount)") } }
        ) : nil
        run.start { await BlacklistChecker().check(ip: target) }
    }

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $ip, placeholder: "IP-адрес", icon: "hand.raised.slash",
                         disabled: run.isRunning, savedHostTool: .blacklist) { start() }
            if let error = run.errorMessage {
                ErrorCard(message: error) { start() }
            } else if let report = run.value {
                summaryCard(report)
            } else if run.isRunning {
                ProgressView().padding(.top, 40)
            }
        } content: {
            if let report = run.value {
                listCard(report)
            } else if !run.isRunning, run.errorMessage == nil {
                ToolIdleHint(
                    icon: "hand.raised.slash",
                    title: "Готово к проверке списков",
                    message: "Проверим IP по спискам DNSBL — тем самым, по которым почтовые серверы решают, принимать ли письмо.",
                    example: "8.8.8.8",
                    current: ip
                ) { ip = "8.8.8.8" }
            }
        } bottom: {
            RunButton(title: "Проверить", running: run.isRunning,
                      disabled: ip.trimmingCharacters(in: .whitespaces).isEmpty) {
                if run.isRunning { return }; start()
            }
        }
        .animation(.snappy, value: run.value?.listedCount)
        // A check runs for seconds; people put the phone down while it does.
        .haptic(.success, trigger: run.isRunning) { !$0 && run.errorMessage == nil }
        .haptic(.failure, trigger: run.isRunning) { !$0 && run.errorMessage != nil }
        .navigationTitle("Блэклисты")
        .toolTitleDisplayMode()
        .onAppear {
            if let presetHost { ip = presetHost }
            if autostart { start() }
        }
    }

    private func summaryCard(_ report: BlacklistReport) -> some View {
        let clean = report.listedCount == 0
        return HStack(spacing: 12) {
            Image(systemName: clean ? "checkmark.shield.fill" : "exclamationmark.octagon.fill")
                .font(.title)
                .foregroundStyle(clean ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                let statusTitle: LocalizedStringKey = clean ? "Чисто" : "В \(report.listedCount) списках"
                Text(statusTitle)
                    .font(.title3.weight(.bold))
                Text("\(report.ip) · проверено \(report.checkedCount) провайдеров")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .card()
    }

    private func listCard(_ report: BlacklistReport) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(report.entries.enumerated()), id: \.element.id) { idx, entry in
                HStack {
                    statusIcon(entry.status)
                    Text(entry.provider.name).font(.callout)
                    Spacer()
                    if entry.status == .listed, !entry.codes.isEmpty {
                        Text(entry.codes.joined(separator: ", "))
                            .font(.caption.monospaced()).foregroundStyle(.red)
                    } else {
                        Text(LocalizedStringKey(statusText(entry.status)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                if idx < report.entries.count - 1 { Divider().padding(.leading, 44) }
            }
        }
        .card()
    }

    private func statusIcon(_ status: BlacklistEntry.Status) -> some View {
        Group {
            switch status {
            case .clean: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .listed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            case .error: Image(systemName: "questionmark.circle.fill").foregroundStyle(.secondary)
            }
        }
    }

    private func statusText(_ status: BlacklistEntry.Status) -> String {
        switch status {
        case .clean: return "чисто"
        case .listed: return "в списке"
        case .error: return "нет ответа"
        }
    }
}
