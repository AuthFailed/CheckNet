import SwiftUI
import Observation
import NetworkKit

@MainActor
@Observable
final class SpeedTestModel {
    enum Phase: Equatable { case idle, loadingServers, pinging, ready, running, done, failed(String) }

    private(set) var phase: Phase = .idle
    private(set) var servers: [IperfServer] = []
    private(set) var pings: [String: Double] = [:]      // host -> latency ms (reachable only)
    var selected: IperfServer?
    private(set) var pingProgress: (done: Int, total: Int) = (0, 0)

    // Live test state
    private(set) var currentPhaseLabel = ""
    private(set) var downloadMbps: Double?
    private(set) var uploadMbps: Double?
    private(set) var samples: [SpeedSample] = []
    private(set) var liveMbps: Double = 0
    private(set) var liveDirection: SpeedDirection = .download

    private var runTask: Task<Void, Never>?
    var useLiveActivity = true

    /// Device region (ISO country) used to surface nearby servers first.
    static let deviceRegion: String = Locale.current.region?.identifier ?? ""

    /// Servers sorted by measured latency (reachable first), then unknown.
    var sortedServers: [IperfServer] {
        servers.sorted { a, b in
            switch (pings[a.host], pings[b.host]) {
            case let (.some(x), .some(y)): return x < y
            case (.some, .none): return true
            case (.none, .some): return false
            default: return false
            }
        }
    }

    /// Servers in the user's own country, nearest first.
    var nearbyServers: [IperfServer] {
        guard !Self.deviceRegion.isEmpty else { return [] }
        return sortedServers.filter { $0.country.caseInsensitiveCompare(Self.deviceRegion) == .orderedSame }
    }

    /// A section of the server list for grouped display.
    struct ServerGroup: Identifiable { let id: String; let title: String; let servers: [IperfServer] }

    /// Grouped for the picker: nearby (same country) first, then by continent.
    var serverGroups: [ServerGroup] {
        let sorted = sortedServers
        var groups: [ServerGroup] = []
        let nearby = nearbyServers
        if !nearby.isEmpty {
            let label = Self.deviceRegion.isEmpty ? "Рядом с вами" : "Рядом с вами (\(Self.deviceRegion))"
            groups.append(ServerGroup(id: "nearby", title: label, servers: nearby))
        }
        let nearbyHosts = Set(nearby.map(\.host))
        let rest = sorted.filter { !nearbyHosts.contains($0.host) }
        let byContinent = Dictionary(grouping: rest) { $0.continent.isEmpty ? "Другие регионы" : $0.continent }
        for key in byContinent.keys.sorted() {
            groups.append(ServerGroup(id: key, title: key, servers: byContinent[key] ?? []))
        }
        return groups
    }

    func loadServers() async {
        guard servers.isEmpty else { return }
        phase = .loadingServers
        do {
            let list = try await IperfServerList().fetch()
            servers = list.filter { $0.supportsReverse }
            phase = .ready
            await pingServers()
        } catch {
            // Fall back to the curated RU servers so the tab still works offline
            // from the public index.
            let fallback = IperfServerList.ertelecomServers.filter { $0.supportsReverse }
            if !fallback.isEmpty {
                servers = fallback
                phase = .ready
                await pingServers()
            } else {
                phase = .failed("Не удалось загрузить список серверов: \(error.localizedDescription)")
            }
        }
    }

    /// Manually refresh the auto-updated server index.
    func refreshServers() async {
        servers = []; pings = [:]; selected = nil
        await loadServers()
    }

    /// Ping (reachability + latency) all servers to show how far each is.
    func pingServers() async {
        guard !servers.isEmpty else { return }
        phase = .pinging
        pings = [:]
        let hosts = servers.map(\.host)
        pingProgress = (0, hosts.count)

        await withTaskGroup(of: (String, Double?).self) { group in
            var iterator = hosts.makeIterator()
            var active = 0
            func addNext() {
                guard let host = iterator.next() else { return }
                active += 1
                group.addTask {
                    let stats = try? await ICMPPinger().measure(host: host, config: .preview)
                    if let stats, stats.received > 0, let avg = stats.avg { return (host, avg) }
                    return (host, nil)
                }
            }
            for _ in 0..<32 { addNext() }
            while active > 0 {
                guard let (host, latency) = await group.next() else { break }
                active -= 1
                pingProgress.done += 1
                if let latency { pings[host] = latency }
                addNext()
            }
        }
        // Auto-select the nearest reachable server, preferring the user's country.
        if selected == nil {
            selected = nearbyServers.first { pings[$0.host] != nil }
                ?? sortedServers.first { pings[$0.host] != nil }
                ?? nearbyServers.first
                ?? sortedServers.first
        }
        phase = .ready
    }

    func startTest(fallbackToCloudflare: Bool = true) {
        guard let server = selected else { return }
        stop()
        samples = []; downloadMbps = nil; uploadMbps = nil; liveMbps = 0
        phase = .running
        // A fresh controller per run, captured by the task, so restarting can't
        // let an old run's teardown end the new activity.
        let activity = useLiveActivity ? CheckActivityController() : nil
        activity?.start(kind: .speed, title: server.site.isEmpty ? server.host : server.site,
                        subtitle: "Скорость", view: speedActivityView(isRunning: true))
        runTask = Task { [weak self] in
            guard let self else { return }
            let config = IperfClient.Config(duration: 12, streams: 6, download: true, upload: true)
            var gotResult = false
            for await event in IperfClient().run(server: server, config: config) {
                if Task.isCancelled { break }
                if handle(event) { gotResult = true }
                await activity?.update(speedActivityView(isRunning: true))
            }
            // Fall back to Cloudflare HTTP if iperf3 produced nothing.
            if !gotResult && fallbackToCloudflare && !Task.isCancelled {
                currentPhaseLabel = "iperf3 недоступен — переключаюсь на HTTP-тест…"
                for await event in CloudflareSpeedTest().run(duration: 12) {
                    if Task.isCancelled { break }
                    _ = handle(event)
                    await activity?.update(speedActivityView(isRunning: true))
                }
            }
            if phase == .running { phase = .done }
            await activity?.end(speedActivityView(isRunning: false))
        }
    }

    private func speedActivityView(isRunning: Bool) -> CheckActivityView {
        SpeedActivityContent.view(
            liveMbps: liveMbps, directionLabel: liveDirection == .download ? "Загрузка" : "Отдача",
            download: downloadMbps, upload: uploadMbps, phaseLabel: currentPhaseLabel, isRunning: isRunning)
    }

    @discardableResult
    private func handle(_ event: SpeedEvent) -> Bool {
        switch event {
        case .phase(let label):
            currentPhaseLabel = label
        case .sample(let s):
            samples.append(s)
            liveMbps = s.mbps
            liveDirection = s.direction
        case .finished(let r):
            downloadMbps = r.downloadMbps
            uploadMbps = r.uploadMbps
            phase = .done
            currentPhaseLabel = ""
            return (r.downloadMbps ?? 0) > 0 || (r.uploadMbps ?? 0) > 0
        case .failed(let reason):
            currentPhaseLabel = reason
        }
        return false
    }

    func stop() {
        runTask?.cancel(); runTask = nil
        if phase == .running { phase = .ready }
        // The run task ends its own activity when the loop breaks on cancellation.
    }
}
