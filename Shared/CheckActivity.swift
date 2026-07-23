import Foundation

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
    /// The big value, e.g. "12 мс" or "3/4".
    var headline: String
    /// A short line under the title, e.g. "идёт проверка" or "не отвечают: 2".
    var caption: String
    var stats: [CheckStat] = []
    var isRunning: Bool
}

/// Builds the Live Activity content for a ping run.
enum PingActivityContent {
    static func statusText(_ status: PingSnapshot.Status) -> String {
        switch status {
        case .ok: return "OK"
        case .degraded: return "Плохо"
        case .down: return "Нет"
        case .unknown: return "…"
        }
    }

    static func view(latency: Double?, loss: Double, received: Int, transmitted: Int,
                     status: PingSnapshot.Status, isRunning: Bool) -> CheckActivityView {
        CheckActivityView(
            status: status,
            headline: latency.map { "\(Int($0)) мс" } ?? "—",
            caption: isRunning ? "идёт проверка" : "завершено",
            stats: [
                CheckStat(label: "Потери", value: "\(Int(loss))%"),
                CheckStat(label: "Пакеты", value: "\(received)/\(transmitted)"),
                CheckStat(label: "Статус", value: statusText(status))
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
        "\(entries.count) хостов"
    }

    static func view(for entries: [MonitoredEntry], isRunning: Bool = true) -> CheckActivityView {
        let online = entries.filter { $0.status == .ok || $0.status == .degraded }.count
        let down = entries.filter { $0.status == .down }.count
        let anyChecked = entries.contains { $0.status != .unknown }
        let caption: String
        if entries.isEmpty { caption = "нет хостов" }
        else if down > 0 { caption = "не отвечают: \(down)" }
        else if anyChecked { caption = "все отвечают" }
        else { caption = "ожидание проверки" }
        return CheckActivityView(
            status: overallStatus(entries),
            headline: "\(online)/\(entries.count)",
            caption: caption,
            stats: [
                CheckStat(label: "Онлайн", value: "\(online)"),
                CheckStat(label: "Не отвечают", value: "\(down)"),
                CheckStat(label: "Хостов", value: "\(entries.count)")
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
            ? "\(Int(liveMbps.rounded())) Мбит/с"
            : (download.map { "\(Int($0.rounded())) Мбит/с" } ?? "—")
        let caption = isRunning ? (phaseLabel.isEmpty ? directionLabel : phaseLabel) : "готово"
        return CheckActivityView(
            status: isRunning ? .unknown : .ok,
            headline: headline,
            caption: caption,
            stats: [
                CheckStat(label: "Загрузка", value: mbps(download)),
                CheckStat(label: "Отдача", value: mbps(upload)),
                CheckStat(label: "Сейчас", value: "\(Int(liveMbps.rounded()))")
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
            headline = latestRTT.map { "\(Int($0.rounded())) мс" } ?? "…"
            caption = phaseLabel
        } else if let grade = gradeLetter {
            headline = grade
            caption = addedLatency.map { "+\(Int($0.rounded())) мс под нагрузкой" } ?? "готово"
        } else {
            headline = "—"
            caption = "готово"
        }
        let stats = isRunning
            ? [CheckStat(label: "Фаза", value: phaseLabel.isEmpty ? "…" : phaseLabel),
               CheckStat(label: "RTT", value: latestRTT.map { "\(Int($0.rounded())) мс" } ?? "—")]
            : [CheckStat(label: "Простой", value: idleRTT.map { "\(Int($0.rounded())) мс" } ?? "—"),
               CheckStat(label: "Нагрузка", value: loadedRTT.map { "\(Int($0.rounded())) мс" } ?? "—"),
               CheckStat(label: "Оценка", value: gradeLetter ?? "—")]
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
            headline: lastAvg.map { "\(Int($0.rounded())) мс" } ?? "\(hopCount) хопов",
            caption: isRunning ? "раунд \(round)" : "готово",
            stats: [
                CheckStat(label: "Хопы", value: "\(hopCount)"),
                CheckStat(label: "Потери", value: "\(Int(lastLoss.rounded()))%"),
                CheckStat(label: "Раунд", value: "\(round)")
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
                                     caption: "выполняется", isRunning: true)
        case .success(let value):
            let d = describe(value)
            return CheckActivityView(status: status(value), headline: d.headline,
                                     caption: d.caption, isRunning: false)
        case .failure(let message):
            return CheckActivityView(status: .down, headline: "Ошибка",
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
            caption: isRunning ? "сканирование" : "готово — \(found) \(foundLabel.lowercased())",
            stats: [
                CheckStat(label: foundLabel, value: "\(found)"),
                CheckStat(label: "Проверено", value: "\(scanned)"),
                CheckStat(label: "Всего", value: "\(total)")
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
            headline: "\(hopCount) хопов",
            caption: isRunning ? "идёт трассировка" : (reached ? "цель достигнута" : "цель не достигнута"),
            stats: [
                CheckStat(label: "Хопы", value: "\(hopCount)"),
                CheckStat(label: "Цель", value: reached ? "достигнута" : (isRunning ? "…" : "нет"))
            ],
            isRunning: isRunning
        )
    }
}
