import SwiftUI
import NetworkKit

@MainActor
@Observable
final class BlacklistModel {
    var ip = "8.8.8.8"
    private(set) var isRunning = false
    private(set) var report: BlacklistReport?

    func run() async {
        let target = ip.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }
        isRunning = true; report = nil
        report = await BlacklistChecker().check(ip: target)
        isRunning = false
    }

    func resolveAndRun(host: String) async {
        if let ep = try? await HostResolver.resolveFirst(host: host, family: .ipv4) {
            ip = ep.ipString
        }
        await run()
    }
}

struct BlacklistView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var model = BlacklistModel()

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $model.ip, placeholder: "IP-адрес", icon: "hand.raised.slash",
                         disabled: model.isRunning, savedHostTool: .blacklist) { Task { await model.run() } }
            if let report = model.report {
                summaryCard(report)
                listCard(report)
            } else if model.isRunning {
                ProgressView().padding(.top, 40)
            }
        } bottom: {
            RunButton(title: "Проверить", running: model.isRunning,
                      disabled: model.ip.trimmingCharacters(in: .whitespaces).isEmpty) {
                if model.isRunning { return }; Task { await model.run() }
            }
        }
        .animation(.snappy, value: model.report?.listedCount)
        .navigationTitle("Блэклисты")
        .toolTitleDisplayMode()
        .onAppear {
            if let presetHost { model.ip = presetHost }
            if autostart { Task { await model.run() } }
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
