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

    func loadServers() async {
        guard servers.isEmpty else { return }
        phase = .loadingServers
        do {
            let list = try await IperfServerList().fetch()
            servers = list.filter { $0.supportsReverse }
            phase = .ready
            await pingServers()
        } catch {
            phase = .failed("Не удалось загрузить список серверов: \(error.localizedDescription)")
        }
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
                    let stats = try? await ICMPPinger().measure(host: host, config: PingConfig(count: 2, interval: 0.2, timeout: 1.5))
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
        // Auto-select the nearest reachable server.
        if selected == nil { selected = sortedServers.first { pings[$0.host] != nil } ?? sortedServers.first }
        phase = .ready
    }

    func startTest(fallbackToCloudflare: Bool = true) {
        guard let server = selected else { return }
        stop()
        samples = []; downloadMbps = nil; uploadMbps = nil; liveMbps = 0
        phase = .running
        runTask = Task { [weak self] in
            guard let self else { return }
            let config = IperfClient.Config(duration: 12, streams: 6, download: true, upload: true)
            var gotResult = false
            for await event in IperfClient().run(server: server, config: config) {
                if Task.isCancelled { return }
                if handle(event) { gotResult = true }
            }
            // Fall back to Cloudflare HTTP if iperf3 produced nothing.
            if !gotResult && fallbackToCloudflare && !Task.isCancelled {
                currentPhaseLabel = "iperf3 недоступен — переключаюсь на HTTP-тест…"
                for await event in CloudflareSpeedTest().run(duration: 12) {
                    if Task.isCancelled { return }
                    _ = handle(event)
                }
            }
            if phase == .running { phase = .done }
        }
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
    }
}
