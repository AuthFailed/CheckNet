import SwiftUI
import NetworkKit

@MainActor
@Observable
final class XrayCheckModel {
    var input = ""
    private(set) var coreVersion: String?
    private(set) var isRunning = false
    private(set) var results: [EgressResult] = []
    private(set) var node: ProxyNode?
    private(set) var errorMessage: String?
    private var task: Task<Void, Never>?

    func loadVersion() { coreVersion = try? XrayCore.version() }

    /// Distinct egress IPs seen across every resource that answered.
    var egressIPs: [String] {
        var seen: [String] = []
        for r in results { if let ip = r.info?.ip, !seen.contains(ip) { seen.append(ip) } }
        return seen
    }

    /// The exit IP most resources agree on — the headline value.
    var primaryIP: String? {
        let ips = results.compactMap { $0.info?.ip }
        guard !ips.isEmpty else { return nil }
        return Dictionary(grouping: ips, by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }

    /// A country code/name to badge the headline IP with (prefer what a source
    /// reported for the primary IP; a 2-letter code gets a flag in the view).
    var dominantCountry: String? {
        let ip = primaryIP
        return results.first(where: { $0.info?.ip == ip && $0.info?.country != nil })?.info?.country
            ?? results.compactMap { $0.info?.country }.first
    }

    var answered: Int { results.filter(\.ok).count }
    var didFinishWithNoAnswers: Bool { !isRunning && !results.isEmpty && answered == 0 }

    func start() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning else { return }
        guard let parsed = SubscriptionParser.parse(text).nodes.first else {
            errorMessage = "Couldn't parse the link or config"; return
        }
        results = []; errorMessage = nil; node = parsed; isRunning = true
        task = Task {
            do {
                let port = try await XrayProxyRunner.startInProcess(node: parsed)
                defer { XrayCore.stop() }
                for await result in EgressIPProbe.stream(socksPort: port) {
                    if Task.isCancelled { break }
                    insert(result)
                }
            } catch {
                errorMessage = (error as? XrayProxyRunner.RunError)?.message ?? error.localizedDescription
            }
            isRunning = false
        }
    }

    /// Keep results grouped by category, fastest first inside each group.
    private func insert(_ result: EgressResult) {
        results.append(result)
        let order = ["IP echo": 0, "Cloudflare": 1, "Geo and ASN": 2]
        results.sort {
            let a = order[$0.category] ?? 9, b = order[$1.category] ?? 9
            if a != b { return a < b }
            if $0.ok != $1.ok { return $0.ok && !$1.ok }
            return $0.millis < $1.millis
        }
    }

    func stop() { task?.cancel(); task = nil; isRunning = false; XrayCore.stop() }
}

/// Xray inbound reachability + exit IP (#71): we paste a `vless://` /
/// `trojan://` link or a config, bring up the Xray core **in-process** (libXray) with
/// a local SOCKS and poll a dozen IP-echo/geo services through it — what
/// exit IP each one sees (provider, Cloudflare, country, ASN). Diagnostics for
/// your own server, not circumvention.
struct XrayCheckView: View {
    var autostart = false
    @State private var model = XrayCheckModel()

    var body: some View {
        ToolScaffold {
            inputCard
            if let error = model.errorMessage {
                ErrorCard(message: error) { model.start() }
            } else if model.primaryIP != nil || model.didFinishWithNoAnswers {
                verdictCard
            }
            if !model.results.isEmpty {
                resultsList
            }
        } content: {
            if model.results.isEmpty, !model.isRunning, model.errorMessage == nil {
                ToolIdleHint(
                    icon: "globe.badge.chevron.backward",
                    title: "Exit IP through your proxy",
                    message: "The Xray core starts in the app, connects to your server and queries various resources through it — which exit IP they see: address and provider country, what Cloudflare shows, ASN.",
                    example: "",
                    current: model.input
                )
            } else if model.isRunning, model.results.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Starting the core and connecting to the server…")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 40)
            }
        } bottom: {
            RunButton(title: "Check", running: model.isRunning,
                      disabled: model.input.trimmingCharacters(in: .whitespaces).isEmpty) {
                if model.isRunning { model.stop() } else { model.start() }
            }
        }
        .animation(.snappy, value: model.results)
        .animation(.snappy, value: model.errorMessage)
        .haptic(.success, trigger: model.isRunning) { !$0 && model.answered > 0 }
        .haptic(.failure, trigger: model.isRunning) { !$0 && (model.errorMessage != nil || model.didFinishWithNoAnswers) }
        .navigationTitle("Xray availability")
        .toolTitleDisplayMode()
        .safeAreaInset(edge: .bottom) {
            if let v = model.coreVersion {
                Text("Xray core \(v)")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.bottom, 2)
            }
        }
        .onAppear {
            model.loadVersion()
            if autostart { model.start() }
        }
    }

    // MARK: - input

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Node link or config", systemImage: "bolt.horizontal.circle")
                .font(.caption).foregroundStyle(.secondary)
            TextField("vless:// · trojan:// · xray json", text: $model.input, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(.callout, design: .monospaced))
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .disabled(model.isRunning)
        }
        .padding(14).card()
    }

    // MARK: - verdict

    private var verdictCard: some View {
        let ok = model.answered > 0
        let split = model.egressIPs.count > 1
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: ok ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.title).foregroundStyle(ok ? Color.green : .red)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ok ? "Inbound works" : "Connection failed")
                        .font(.headline)
                    Text(ok
                         ? "\(model.answered) of \(model.results.count) resources responded."
                         : "The core started, but no request went through the proxy.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
            .padding(14)
            if let ip = model.primaryIP {
                Divider().padding(.leading, 14)
                HStack(spacing: 10) {
                    if let flag = flagEmoji(model.dominantCountry) {
                        Text(flag).font(.title2)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Exit IP").font(.caption2).foregroundStyle(.secondary)
                        Text(ip).font(.system(.title3, design: .monospaced).weight(.semibold))
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 8)
                }
                .padding(14)
                if split {
                    Divider().padding(.leading, 14)
                    Label("Resources see different exit IPs: \(model.egressIPs.joined(separator: ", "))",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                        .padding(14)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card()
    }

    // MARK: - list

    private var resultsList: some View {
        let groups = ["IP echo", "Cloudflare", "Geo and ASN"]
        return ForEach(groups, id: \.self) { group in
            let rows = model.results.filter { $0.category == group }
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(group).font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        if i > 0 { Divider().padding(.leading, 14) }
                        EgressRow(result: row)
                    }
                }
                .card()
            }
        }
    }

    private func flagEmoji(_ country: String?) -> String? {
        guard let c = country, c.count == 2, c.allSatisfy(\.isLetter) else { return nil }
        return CountryFlag.flag(c)
    }
}

/// One resource's answer: name + latency on the left, egress IP and geo/ASN on
/// the right; a red dot and reason when it didn't answer.
private struct EgressRow: View {
    let result: EgressResult

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.ok ? Color.green : .red)
                .accessibilityLabel(result.ok ? "Responded" : "No response")
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name).font(.subheadline.weight(.medium))
                if let info = result.info {
                    Text(info.ip).font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary).textSelection(.enabled)
                    if let detail = detailLine(info) {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let err = result.error {
                    Text(err).font(.caption).foregroundStyle(.red.opacity(0.9))
                }
            }
            Spacer(minLength: 8)
            if result.ok {
                Text("\(Int(result.millis)) ms").font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    private func detailLine(_ info: EgressInfo) -> String? {
        var parts: [String] = []
        if let c = info.country { parts.append(flagged(c)) }
        if let org = info.org { parts.append(org) }
        if let asn = info.asn, info.org == nil || !asn.contains(" ") { parts.append(asn) }
        if let note = info.note { parts.append(note) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func flagged(_ country: String) -> String {
        guard country.count == 2, country.allSatisfy(\.isLetter) else { return country }
        return "\(CountryFlag.flag(country)) \(country)"
    }
}
