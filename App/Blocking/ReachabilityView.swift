import SwiftUI
import NetworkKit

/// "What exactly can't I reach" — sweeps a group of hosts and shows the result
/// per provider.
struct ReachabilityView: View {
    @State private var scope: ProbeTarget.Category = .foreignInfrastructure
    @State private var fingerprint: TLSFingerprint = .system
    @State private var run = ToolRunModel<Sweep>()

    /// The sweep's two outputs: per-host results and the overall verdict.
    private struct Sweep: Sendable {
        let results: [ReachabilityResult]
        let finding: CensorshipFinding?
    }

    private var targets: [ProbeTarget] { ProbeCatalog.targets(in: scope) }
    private var results: [ReachabilityResult] { run.value?.results ?? [] }
    private var summaries: [ProviderSummary] { ReachabilitySweep().summarise(results) }

    /// Awaitable so pull-to-refresh keeps its spinner until the sweep finishes.
    private func performSweep() async {
        let scope = scope, fingerprint = fingerprint
        await run.perform {
            let sweep = ReachabilitySweep(fingerprint: fingerprint)
            // Include the domestic control group so the verdict can distinguish
            // "this provider is filtered" from "the connection is down".
            var targetsToRun = ProbeCatalog.targets(in: scope)
            if scope == .foreignInfrastructure {
                targetsToRun += ProbeCatalog.targets(in: .russianInfrastructure)
            }
            let collected = await sweep.run(targets: targetsToRun)
            return Sweep(results: collected, finding: sweep.verdict(for: collected))
        } onSuccess: { sweep in
            WebhookReporter.reportReachability(
                scope: scope.rawValue, results: sweep.results,
                verdict: (sweep.finding?.verdict ?? .inconclusive).rawValue
            )
        }
    }

    private func start() {
        guard !run.isRunning else { return }
        Task { await performSweep() }
    }

    var body: some View {
        List {
            Section {
                Picker("Group", selection: $scope) {
                    ForEach(ProbeTarget.Category.allCases, id: \.self) { category in
                        Text(LocalizedStringKey(category.label)).tag(category)
                    }
                }
                Picker("Connection profile", selection: $fingerprint) {
                    ForEach(TLSFingerprint.allCases) { Text(LocalizedStringKey($0.label)).tag($0) }
                }
            } footer: {
                Text("The profile changes what the TLS handshake looks like. It isn’t a full browser imitation — the system decides the order of extensions. But if one profile gets through and another is cut off, the restriction depends on the kind of connection.")
            }

            if let finding = run.value?.finding {
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

            if !results.isEmpty {
                Section("By provider") {
                    ForEach(summaries) { summary in
                        HStack {
                            Text(summary.provider)
                            Spacer()
                            Text("\(summary.reachable)/\(summary.total)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(summary.fullyObstructed ? .red : .secondary)
                        }
                    }
                }

                Section("Hosts") {
                    ForEach(results) { result in
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
                                Text("\(Int(ms)) ms").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            } else if !run.isRunning {
                Section {
                    ContentUnavailableView(
                        "Check hasn’t been run",
                        systemImage: "network",
                        description: Text("\(targets.count) hosts will be checked. Catalog from \(ProbeCatalog.revision).")
                    )
                }
            }
        }
        .navigationTitle("Availability")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        // This screen opens straight from a NavigationLink, bypassing the
        // ToolDestinationView that gives every other tool its ⓘ, so it carries
        // its own — every check explains itself.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                InfoButton(title: "Host reachability", systemImage: "network",
                           message: "Checks one reference node per provider, service and push-notification server — whether it responds and whether the network interferes. The connection profile changes the TLS handshake: if one passes and another is cut, the restriction depends on the connection type.")
            }
        }
        .refreshable { await performSweep() }
        .safeAreaInset(edge: .bottom) {
            RunButton(title: "Check", running: run.isRunning, disabled: false) {
                if run.isRunning { return }
                start()
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
