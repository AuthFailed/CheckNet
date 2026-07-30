import Foundation

/// Localizes a Live Activity string through `Bundle.main.localizedString` — the
/// same path `Text`/`LocalizedStringKey` use, so it honours the app's in-app
/// language switch (see `LanguageBundle`). `String(localized:)` bypasses that
/// override and would fall back to the system language. Content is always built
/// in the app process, so the widget just renders the already-localized result.
private func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// `L` for a format key with arguments, e.g. `Lf("round %lld", round)`.
private func Lf(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: .current, arguments: args)
}

/// Which check a Live Activity represents — drives the icon and the interactive
/// button in the widget.
enum CheckActivityKind: String, Codable, Sendable {
    case ping, monitor, speed, bufferbloat, mtr, traceroute, portScan, ipScan
    /// One-shot lookups on `ToolRunModel` (host→IP, DNS, whois, TLS…). The
    /// subtitle names the specific tool.
    case lookup
    case worldPing, mtu, bonjour, browser
}

/// One label/value chip shown in a check's Live Activity (expanded Dynamic
/// Island and Lock Screen).
struct CheckStat: Codable, Hashable, Sendable {
    var label: String
    var value: String
}

/// A plain, platform-agnostic snapshot of what a check's Live Activity should
/// show right now. Producers (ping, monitor) build one of these; the ActivityKit
/// layer mirrors it into a `ContentState`.
///
/// Deliberately ActivityKit-free so the content builders below are unit-testable
/// on macOS, where Live Activities do not exist.
struct CheckActivityView: Equatable, Sendable {
    var status: PingSnapshot.Status
    /// The big value, e.g. "12 ms" or "3/4".
    var headline: String
    /// A short line under the title, e.g. "check in progress" or "not responding: 2".
    var caption: String
    var stats: [CheckStat] = []
    var isRunning: Bool
}

/// Builds the Live Activity content for a ping run.
enum PingActivityContent {
    static func statusText(_ status: PingSnapshot.Status) -> String {
        switch status {
        case .ok: return "OK"
        case .degraded: return L("Poor")
        case .down: return L("No")
        case .unknown: return "…"
        }
    }

    static func view(latency: Double?, loss: Double, received: Int, transmitted: Int,
                     status: PingSnapshot.Status, isRunning: Bool) -> CheckActivityView {
        CheckActivityView(
            status: status,
            headline: latency.map { Lf("%lld ms", Int($0)) } ?? "—",
            caption: isRunning ? L("testing") : L("done"),
            stats: [
                CheckStat(label: L("Loss"), value: "\(Int(loss))%"),
                CheckStat(label: L("Packets"), value: "\(received)/\(transmitted)"),
                CheckStat(label: L("Status"), value: statusText(status))
            ],
            isRunning: isRunning
        )
    }
}

/// Aggregates the monitored hosts into a single glanceable Live Activity view.
enum MonitorActivityContent {
    /// Overall status is the worst any host is in: one host down colours the
    /// whole activity red.
    static func overallStatus(_ entries: [MonitoredEntry]) -> PingSnapshot.Status {
        if entries.contains(where: { $0.status == .down }) { return .down }
        if entries.contains(where: { $0.status == .degraded }) { return .degraded }
        if entries.contains(where: { $0.status != .unknown }) { return .ok }
        return .unknown
    }

    static func subtitle(for entries: [MonitoredEntry]) -> String {
        Lf("%lld hosts", entries.count)
    }

    static func view(for entries: [MonitoredEntry], isRunning: Bool = true) -> CheckActivityView {
        let online = entries.filter { $0.status == .ok || $0.status == .degraded }.count
        let down = entries.filter { $0.status == .down }.count
        let anyChecked = entries.contains { $0.status != .unknown }
        let caption: String
        if entries.isEmpty { caption = L("no hosts") }
        else if down > 0 { caption = Lf("not responding: %lld", down) }
        else if anyChecked { caption = L("all responding") }
        else { caption = L("awaiting check") }
        return CheckActivityView(
            status: overallStatus(entries),
            headline: "\(online)/\(entries.count)",
            caption: caption,
            stats: [
                CheckStat(label: L("Online"), value: "\(online)"),
                CheckStat(label: L("Down"), value: "\(down)"),
                CheckStat(label: L("Hosts"), value: "\(entries.count)")
            ],
            isRunning: isRunning
        )
    }
}

/// Live Activity content for a speed test. The producer passes the direction as
/// a ready label so this stays free of NetworkKit types.
enum SpeedActivityContent {
    private static func mbps(_ value: Double?) -> String { value.map { "\(Int($0.rounded()))" } ?? "—" }

    static func view(liveMbps: Double, directionLabel: String, download: Double?, upload: Double?,
                     phaseLabel: String, isRunning: Bool) -> CheckActivityView {
        let headline = isRunning
            ? Lf("%lld Mbps", Int(liveMbps.rounded()))
            : (download.map { Lf("%lld Mbps", Int($0.rounded())) } ?? "—")
        let caption = isRunning ? (phaseLabel.isEmpty ? directionLabel : phaseLabel) : L("done")
        return CheckActivityView(
            status: isRunning ? .unknown : .ok,
            headline: headline,
            caption: caption,
            stats: [
                CheckStat(label: L("Download"), value: mbps(download)),
                CheckStat(label: L("Upload"), value: mbps(upload)),
                CheckStat(label: L("Now"), value: "\(Int(liveMbps.rounded()))")
            ],
            isRunning: isRunning
        )
    }
}

/// Live Activity content for the bufferbloat test.
enum BufferbloatActivityContent {
    /// Maps the A–F grade to a status colour: A/B good, C shaky, D/F bad.
    static func status(gradeLetter: String?) -> PingSnapshot.Status {
        switch gradeLetter?.uppercased() {
        case "A", "B": return .ok
        case "C": return .degraded
        case "D", "F": return .down
        default: return .unknown
        }
    }

    static func view(phaseLabel: String, latestRTT: Double?, gradeLetter: String?,
                     addedLatency: Double?, idleRTT: Double?, loadedRTT: Double?,
                     isRunning: Bool) -> CheckActivityView {
        let headline: String
        let caption: String
        if isRunning {
            headline = latestRTT.map { Lf("%lld ms", Int($0.rounded())) } ?? "…"
            caption = phaseLabel
        } else if let grade = gradeLetter {
            headline = grade
            caption = addedLatency.map { Lf("+%lld ms under load", Int($0.rounded())) } ?? L("done")
        } else {
            headline = "—"
            caption = L("done")
        }
        let stats = isRunning
            ? [CheckStat(label: L("Phase"), value: phaseLabel.isEmpty ? "…" : phaseLabel),
               CheckStat(label: "RTT", value: latestRTT.map { Lf("%lld ms", Int($0.rounded())) } ?? "—")]
            : [CheckStat(label: L("Idle"), value: idleRTT.map { Lf("%lld ms", Int($0.rounded())) } ?? "—"),
               CheckStat(label: L("Loaded"), value: loadedRTT.map { Lf("%lld ms", Int($0.rounded())) } ?? "—"),
               CheckStat(label: L("Grade"), value: gradeLetter ?? "—")]
        return CheckActivityView(
            status: isRunning ? .unknown : status(gradeLetter: gradeLetter),
            headline: headline, caption: caption, stats: stats, isRunning: isRunning)
    }
}

/// Live Activity content for MTR — the destination hop drives status and latency.
enum MTRActivityContent {
    static func view(host: String, round: Int, hopCount: Int, lastLoss: Double,
                     lastAvg: Double?, isRunning: Bool) -> CheckActivityView {
        let status: PingSnapshot.Status = (isRunning && hopCount == 0)
            ? .unknown
            : PingSnapshot.status(loss: lastLoss, latency: lastAvg)
        return CheckActivityView(
            status: status,
            headline: lastAvg.map { Lf("%lld ms", Int($0.rounded())) } ?? Lf("%lld hops", hopCount),
            caption: isRunning ? Lf("round %lld", round) : L("done"),
            stats: [
                CheckStat(label: L("Hops"), value: "\(hopCount)"),
                CheckStat(label: L("Loss"), value: "\(Int(lastLoss.rounded()))%"),
                CheckStat(label: L("Round"), value: "\(round)")
            ],
            isRunning: isRunning
        )
    }
}

/// Generic Live Activity content for a one-shot lookup driven by `ToolRunModel`.
/// The tool supplies a short "running" label and, on success, a headline +
/// caption describing its result; failures render uniformly.
enum LookupActivityContent {
    static func view<V>(_ phase: RunPhase<V>, running: String,
                        status: (V) -> PingSnapshot.Status = { _ in .ok },
                        describe: (V) -> (headline: String, caption: String)) -> CheckActivityView {
        switch phase {
        case .idle, .running:
            return CheckActivityView(status: .unknown, headline: running,
                                     caption: L("running"), isRunning: true)
        case .success(let value):
            let d = describe(value)
            return CheckActivityView(status: status(value), headline: d.headline,
                                     caption: d.caption, isRunning: false)
        case .failure(let message):
            return CheckActivityView(status: .down, headline: L("Error"),
                                     caption: String(message.prefix(60)), isRunning: false)
        }
    }
}

/// Live Activity content for a progress scan (ports or an IP range): a running
/// "X/Y" progress plus how many were found. `foundLabel` distinguishes open
/// ports from live hosts.
enum ScanActivityContent {
    static func view(foundLabel: String, found: Int, scanned: Int, total: Int,
                     isRunning: Bool) -> CheckActivityView {
        CheckActivityView(
            status: isRunning ? .unknown : .ok,
            headline: total > 0 ? "\(scanned)/\(total)" : "\(scanned)",
            caption: isRunning ? L("scanning") : Lf("done — %lld %@", found, foundLabel.lowercased() as NSString),
            stats: [
                CheckStat(label: foundLabel, value: "\(found)"),
                CheckStat(label: L("Scanned"), value: "\(scanned)"),
                CheckStat(label: L("Total"), value: "\(total)")
            ],
            isRunning: isRunning
        )
    }
}

/// Live Activity content for traceroute — hops accumulate until the target is reached.
enum TracerouteActivityContent {
    static func view(host: String, hopCount: Int, reached: Bool, isRunning: Bool) -> CheckActivityView {
        CheckActivityView(
            status: isRunning ? .unknown : (reached ? .ok : .degraded),
            headline: Lf("%lld hops", hopCount),
            caption: isRunning ? L("tracing") : (reached ? L("target reached") : L("target not reached")),
            stats: [
                CheckStat(label: L("Hops"), value: "\(hopCount)"),
                CheckStat(label: L("Target"), value: reached ? L("reached") : (isRunning ? "…" : L("no")))
            ],
            isRunning: isRunning
        )
    }
}
