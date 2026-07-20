import Foundation

/// Result of reaching one catalogue target.
public struct ReachabilityResult: Sendable, Hashable, Identifiable {
    public enum Status: String, Sendable, Codable {
        /// TLS handshake completed.
        case reachable
        /// Failed in a way consistent with interference (reset / silent drop).
        case obstructed
        /// Failed in a way that points at the host or routing, not filtering.
        case unavailable

        public var label: String {
            switch self {
            case .reachable: "доступен"
            case .obstructed: "обрыв"
            case .unavailable: "нет ответа"
            }
        }
    }

    public var id: String { target.id }
    public let target: ProbeTarget
    public let status: Status
    public let failure: ProbeFailureKind?
    public let handshakeMillis: Double?
    public let resolvedIP: String?
}

/// Per-provider roll-up of a sweep.
public struct ProviderSummary: Sendable, Hashable, Identifiable {
    public var id: String { provider }
    public let provider: String
    public let reachable: Int
    public let obstructed: Int
    public let unavailable: Int

    public var total: Int { reachable + obstructed + unavailable }
    /// True when every live probe to this provider failed the same way — the
    /// pattern that suggests the provider's network is what's filtered.
    public var fullyObstructed: Bool { obstructed > 0 && reachable == 0 }
}

/// Checks whether the user can reach a set of hosts at all — one target, one
/// provider, or the whole catalogue.
///
/// This answers a question the per-mechanism checks don't: *what* is broken.
/// "Every Hetzner and DigitalOcean host fails while Selectel is fine" is a
/// conclusion a user can act on.
public struct ReachabilitySweep: Sendable {
    public init() {}

    /// Deliberately low. Opening many simultaneous TLS connections is itself a
    /// trigger for connection-rate policing (reported to fire around a dozen),
    /// so a wide sweep would manufacture the very failure it reports.
    public static let concurrency = 4

    public static let handshakeTimeout: TimeInterval = 6

    // MARK: - Single target

    public func check(_ target: ProbeTarget, timeout: TimeInterval = ReachabilitySweep.handshakeTimeout) async -> ReachabilityResult {
        let start = MonoClock.nanos()
        do {
            let endpoint = try await HostResolver.resolveFirst(host: target.host, port: 443)
            let stream = try TLSStream(ip: endpoint.ipString, port: 443, serverName: target.host)
            defer { stream.close() }
            try await stream.open(timeout: timeout)
            return ReachabilityResult(
                target: target, status: .reachable, failure: nil,
                handshakeMillis: MonoClock.millisSince(start), resolvedIP: endpoint.ipString
            )
        } catch {
            let kind = ProbeFailureKind.classify(error)
            return ReachabilityResult(
                target: target,
                status: kind.suggestsInterference ? .obstructed : .unavailable,
                failure: kind, handshakeMillis: nil, resolvedIP: nil
            )
        }
    }

    // MARK: - Sweep

    /// Runs every target in `targets`, at most `concurrency` at a time.
    /// `progress` fires per completed target so a long sweep can fill in live.
    public func run(
        targets: [ProbeTarget],
        timeout: TimeInterval = ReachabilitySweep.handshakeTimeout,
        progress: (@Sendable (ReachabilityResult) -> Void)? = nil
    ) async -> [ReachabilityResult] {
        guard !targets.isEmpty else { return [] }
        var results: [ReachabilityResult] = []
        results.reserveCapacity(targets.count)

        await withTaskGroup(of: ReachabilityResult.self) { group in
            var next = 0
            let limit = min(Self.concurrency, targets.count)
            for _ in 0..<limit {
                let target = targets[next]; next += 1
                group.addTask { await check(target, timeout: timeout) }
            }
            while let finished = await group.next() {
                results.append(finished)
                progress?(finished)
                if next < targets.count {
                    let target = targets[next]; next += 1
                    group.addTask { await check(target, timeout: timeout) }
                }
            }
        }

        // Task completion order is arbitrary; restore catalogue order.
        let position = Dictionary(uniqueKeysWithValues: targets.enumerated().map { ($0.element.id, $0.offset) })
        return results.sorted { (position[$0.id] ?? 0) < (position[$1.id] ?? 0) }
    }

    public func run(
        category: ProbeTarget.Category,
        timeout: TimeInterval = ReachabilitySweep.handshakeTimeout,
        progress: (@Sendable (ReachabilityResult) -> Void)? = nil
    ) async -> [ReachabilityResult] {
        await run(targets: ProbeCatalog.targets(in: category), timeout: timeout, progress: progress)
    }

    // MARK: - Summary

    public func summarise(_ results: [ReachabilityResult]) -> [ProviderSummary] {
        var order: [String] = []
        var buckets: [String: [ReachabilityResult]] = [:]
        for result in results {
            if buckets[result.target.provider] == nil { order.append(result.target.provider) }
            buckets[result.target.provider, default: []].append(result)
        }
        return order.map { provider in
            let group = buckets[provider] ?? []
            return ProviderSummary(
                provider: provider,
                reachable: group.filter { $0.status == .reachable }.count,
                obstructed: group.filter { $0.status == .obstructed }.count,
                unavailable: group.filter { $0.status == .unavailable }.count
            )
        }
    }

    /// Turns a sweep into a verdict, comparing foreign providers against the
    /// domestic control group.
    public func verdict(for results: [ReachabilityResult]) -> CensorshipFinding {
        let foreign = results.filter { $0.target.category == .foreignInfrastructure }
        let domestic = results.filter { $0.target.category == .russianInfrastructure }

        let foreignObstructed = foreign.filter { $0.status == .obstructed }
        let foreignReachable = foreign.filter { $0.status == .reachable }
        let domesticReachable = domestic.filter { $0.status == .reachable }

        var evidence = summarise(results).map { summary in
            "\(summary.provider): доступно \(summary.reachable) из \(summary.total)"
                + (summary.obstructed > 0 ? ", обрывов \(summary.obstructed)" : "")
        }

        guard !foreign.isEmpty else {
            return CensorshipFinding(
                verdict: .inconclusive,
                headline: "Недостаточно данных",
                detail: "В прогоне не было зарубежных целей, сравнивать не с чем.",
                evidence: evidence
            )
        }

        // Everything failing, including domestic, means the connection is down —
        // not that everything is filtered.
        if foreignReachable.isEmpty && domesticReachable.isEmpty && !domestic.isEmpty {
            return CensorshipFinding(
                verdict: .inconclusive,
                headline: "Сеть недоступна",
                detail: "Не удалось подключиться ни к зарубежным, ни к российским узлам. Похоже на общий обрыв связи, а не на фильтрацию.",
                evidence: evidence
            )
        }

        let obstructedProviders = Set(foreignObstructed.map(\.target.provider)).sorted()
        if !obstructedProviders.isEmpty {
            evidence.append("Обрывы у: \(obstructedProviders.joined(separator: ", "))")
            if !domesticReachable.isEmpty {
                evidence.append("Российские узлы при этом отвечают — ограничение зависит от назначения.")
            }
            return CensorshipFinding(
                verdict: .restricted,
                headline: "Часть зарубежных провайдеров недоступна",
                detail: "Соединения обрываются у \(obstructedProviders.count) провайдеров: \(obstructedProviders.joined(separator: ", ")). Доступно \(foreignReachable.count) из \(foreign.count) зарубежных узлов.",
                evidence: evidence
            )
        }

        return CensorshipFinding(
            verdict: .clean,
            headline: "Все узлы доступны",
            detail: "Проверено \(results.count) узлов, обрывов соединения не зафиксировано.",
            evidence: evidence
        )
    }
}
