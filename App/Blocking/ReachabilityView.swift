import SwiftUI
import NetworkKit

/// "What exactly can't I reach" — sweeps a group of hosts and shows the result
/// per provider.
@MainActor
@Observable
final class ReachabilityModel {
    var scope: ProbeTarget.Category = .foreignInfrastructure
    var fingerprint: TLSFingerprint = .system
    private(set) var isRunning = false
    private(set) var results: [ReachabilityResult] = []
    private(set) var finding: CensorshipFinding?

    var targets: [ProbeTarget] { ProbeCatalog.targets(in: scope) }

    func run() async {
        isRunning = true
        results = []
        finding = nil

        let sweep = ReachabilitySweep(fingerprint: fingerprint)
        // Include the domestic control group so the verdict can distinguish
        // "this provider is filtered" from "the connection is down".
        var targetsToRun = ProbeCatalog.targets(in: scope)
        if scope == .foreignInfrastructure {
            targetsToRun += ProbeCatalog.targets(in: .russianInfrastructure)
        }

        let collected = await sweep.run(targets: targetsToRun)
        results = collected
        finding = sweep.verdict(for: collected)
        isRunning = false

        WebhookReporter.reportReachability(
            scope: scope.rawValue, results: collected,
            verdict: (finding?.verdict ?? .inconclusive).rawValue
        )
    }

    var summaries: [ProviderSummary] {
        ReachabilitySweep().summarise(results)
    }
}

struct ReachabilityView: View {
    @State private var model = ReachabilityModel()

    var body: some View {
        List {
            Section {
                Picker("Группа", selection: Binding(
                    get: { model.scope },
                    set: { model.scope = $0 }
                )) {
                    ForEach(ProbeTarget.Category.allCases, id: \.self) { category in
                        Text(LocalizedStringKey(category.label)).tag(category)
                    }
                }
                Picker("Профиль соединения", selection: Binding(
                    get: { model.fingerprint },
                    set: { model.fingerprint = $0 }
                )) {
                    ForEach(TLSFingerprint.allCases) { Text(LocalizedStringKey($0.label)).tag($0) }
                }
            } footer: {
                Text("Профиль меняет вид TLS-рукопожатия. Это не полная имитация браузера — порядок расширений задаёт система. Но если один профиль проходит, а другой обрывается, ограничение зависит от вида соединения.")
            }

            if let finding = model.finding {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: symbol(finding.verdict))
                            .font(.title)
                            .foregroundStyle(color(finding.verdict))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(finding.headline)).font(.headline)
                            Text(LocalizedStringKey(finding.detail)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !model.results.isEmpty {
                Section("По провайдерам") {
                    ForEach(model.summaries) { summary in
                        HStack {
                            Text(summary.provider)
                            Spacer()
                            Text("\(summary.reachable)/\(summary.total)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(summary.fullyObstructed ? .red : .secondary)
                        }
                    }
                }

                Section("Узлы") {
                    ForEach(model.results) { result in
                        HStack(spacing: 10) {
                            StatusDot(level: level(for: result.status),
                                      label: LocalizedStringKey(result.status.label))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.target.host).font(.callout)
                                Text("\(result.target.provider) · \(result.status.label)"
                                     + (result.failure.map { " · \($0.label)" } ?? ""))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let ms = result.handshakeMillis {
                                Text("\(Int(ms)) мс").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            } else if !model.isRunning {
                Section {
                    ContentUnavailableView(
                        "Проверка не запускалась",
                        systemImage: "network",
                        description: Text("Будет проверено узлов: \(model.targets.count). Каталог от \(ProbeCatalog.revision).")
                    )
                }
            }
        }
        .navigationTitle("Доступность")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        // This screen opens straight from a NavigationLink, bypassing the
        // ToolDestinationView that gives every other tool its ⓘ, so it carries
        // its own — every check explains itself.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                InfoButton(title: "Доступность узлов", systemImage: "network",
                           message: "Проверяет по одному эталонному узлу для каждого провайдера, сервиса и сервера push-уведомлений — отвечает ли он и не мешает ли сеть. Профиль соединения меняет вид TLS-рукопожатия: если один проходит, а другой обрывается, ограничение зависит от вида соединения.")
            }
        }
        .refreshable { await model.run() }
        .safeAreaInset(edge: .bottom) {
            RunButton(title: "Проверить", running: model.isRunning, disabled: false) {
                if model.isRunning { return }
                Task { await model.run() }
            }
        }
    }

    private func level(for status: ReachabilityResult.Status) -> StatusDot.Level {
        switch status {
        case .reachable: .ok
        case .obstructed: .bad
        case .unavailable: .warning
        }
    }

    private func symbol(_ verdict: CensorshipVerdict) -> String {
        switch verdict {
        case .clean: "checkmark.shield.fill"
        case .restricted: "exclamationmark.shield.fill"
        case .inconclusive: "questionmark.circle.fill"
        }
    }

    private func color(_ verdict: CensorshipVerdict) -> Color {
        switch verdict {
        case .clean: .green
        case .restricted: .red
        case .inconclusive: .orange
        }
    }
}
