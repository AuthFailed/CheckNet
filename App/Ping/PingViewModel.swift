import SwiftUI
import Observation
import NetworkKit

enum ProbeType: String, CaseIterable, Identifiable {
    case icmp = "ICMP"
    case tcp = "TCP"
    var id: String { rawValue }
}

enum PingPhase: Equatable {
    case idle
    case running
    case finished
    case failed(String)
}

/// Drives the Ping screen: owns settings, runs the engine, and exposes live state.
@MainActor
@Observable
final class PingViewModel {
    // Input
    var host: String = "google.com"

    // Settings
    var probeType: ProbeType = .icmp
    var packetSize: Int = 56
    var continuous: Bool = false
    var count: Int = 10
    var interval: Double = 1.0
    var timeout: Double = 2.0
    var ttl: Int = 64
    var dontFragment: Bool = false
    var reverseDNS: Bool = true
    var tcpPort: Int = 443

    // Live state
    private(set) var phase: PingPhase = .idle
    private(set) var resolvedIP: String = ""
    private(set) var reverseName: String?
    private(set) var replies: [PingReply] = []           // newest first
    private(set) var stats = PingStatistics(host: "", resolvedIP: "")
    private(set) var lastRTT: Double?
    private(set) var lastError: String?
    private(set) var elapsedSeconds: Double = 0

    private var runTask: Task<Void, Never>?
    private var startDate: Date?
    private let liveActivity = PingLiveActivityController()
    /// When true, the run drives a Live Activity / Dynamic Island.
    var useLiveActivity = true

    var isRunning: Bool { phase == .running }

    /// RTT series in chronological order for charts (capped).
    var rttSeries: [Double] { stats.rttSamples }

    /// Recent RTTs for the live sparkline.
    var sparkline: [Double] { Array(stats.rttSamples.suffix(40)) }

    func toggle() { isRunning ? stop() : start() }

    func start() {
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        stop()
        reset()
        phase = .running
        startDate = Date()

        let targetHost = host.trimmingCharacters(in: .whitespaces)
        let cfg = makeConfig()
        let type = probeType
        let port = tcpPort
        let wantRDNS = reverseDNS

        runTask = Task { [weak self] in
            switch type {
            case .icmp:
                await self?.runICMP(host: targetHost, config: cfg, reverseDNS: wantRDNS)
            case .tcp:
                await self?.runTCP(host: targetHost, port: port, config: cfg, reverseDNS: wantRDNS)
            }
        }
    }

    func stop() {
        // Cancelling lets each run loop fall through to `finishRun()`, which
        // ends the Live Activity, records the result, and sets `.finished`.
        runTask?.cancel()
        runTask = nil
    }

    private func reset() {
        replies = []
        stats = PingStatistics(host: host, resolvedIP: "")
        lastRTT = nil
        lastError = nil
        resolvedIP = ""
        reverseName = nil
        elapsedSeconds = 0
    }

    private func makeConfig() -> PingConfig {
        PingConfig(
            count: continuous ? nil : max(1, count),
            interval: max(0.1, interval),
            timeout: max(0.2, timeout),
            payloadSize: max(0, packetSize),
            ttl: ttl,
            dontFragment: dontFragment
        )
    }

    // MARK: ICMP run

    private func runICMP(host: String, config: PingConfig, reverseDNS: Bool) async {
        let pinger = ICMPPinger()
        for await event in pinger.ping(host: host, config: config) {
            if Task.isCancelled { break }
            switch event {
            case .started(let ip, _):
                resolvedIP = ip
                if useLiveActivity { liveActivity.start(host: host, ip: ip) }
                if reverseDNS { Task { await self.resolveReverse(ip) } }
            case .reply(let reply):
                ingest(reply)
                await updateLiveActivity()
            case .timeout:
                stats.transmitted = max(stats.transmitted, stats.received + 1)
                bumpElapsed()
                await updateLiveActivity()
            case .icmpError(_, let message):
                lastError = message
                bumpElapsed()
            case .failed(let reason):
                phase = .failed(reason)
                if useLiveActivity {
                    await liveActivity.end(latency: nil, loss: 100, received: 0, transmitted: 0, status: .down)
                }
                return
            case .finished(let s):
                stats = s
                await finishRun()
            }
        }
        if phase == .running { await finishRun() }
    }

    // MARK: TCP run

    private func runTCP(host: String, port: Int, config: PingConfig, reverseDNS: Bool) async {
        // Resolve once up front so a bad host fails visibly instead of looking like loss.
        do {
            let ep = try await HostResolver.resolveFirst(host: host, port: UInt16(port))
            resolvedIP = ep.ipString
            if reverseDNS { Task { await self.resolveReverse(ep.ipString) } }
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return
        }

        let scanner = PortScanner()
        var seq = 0
        let total = config.count
        while !Task.isCancelled {
            if let total, seq >= total { break }
            let result = await scanner.check(host: host, port: port, timeout: config.timeout)
            if Task.isCancelled { break }
            stats.transmitted += 1
            if result.isOpen, let latency = result.latencyMillis {
                let reply = PingReply(sequence: seq, bytes: 0, ttl: nil, rttMillis: latency, sourceIP: resolvedIP)
                ingest(reply)
            } else {
                if let err = result.error { lastError = err }
                bumpElapsed()
            }
            seq += 1
            if total == nil || seq < (total ?? .max) {
                try? await Task.sleep(for: .seconds(config.interval))
            }
        }
        await finishRun()
    }

    // MARK: Ingest helpers

    private func ingest(_ reply: PingReply) {
        lastRTT = reply.rttMillis
        stats.received += 1
        stats.transmitted = max(stats.transmitted, reply.sequence + 1)
        stats.rttSamples.append(reply.rttMillis)
        replies.insert(reply, at: 0)
        if replies.count > 200 { replies.removeLast(replies.count - 200) }
        if stats.resolvedIP.isEmpty { stats.resolvedIP = reply.sourceIP }
        bumpElapsed()
    }

    private func bumpElapsed() {
        if let startDate { elapsedSeconds = Date().timeIntervalSince(startDate) }
    }

    private func currentStatus() -> PingSnapshot.Status {
        PingSnapshot.status(loss: stats.lossPercent, latency: lastRTT ?? stats.avg)
    }

    private func updateLiveActivity() async {
        guard useLiveActivity else { return }
        await liveActivity.update(latency: lastRTT, loss: stats.lossPercent,
                                  received: stats.received, transmitted: stats.transmitted,
                                  status: currentStatus())
    }

    private func finishRun() async {
        bumpElapsed()
        if phase == .running { phase = .finished }
        let status = PingSnapshot.status(loss: stats.lossPercent, latency: stats.avg)
        if useLiveActivity {
            await liveActivity.end(latency: stats.avg, loss: stats.lossPercent,
                                   received: stats.received, transmitted: stats.transmitted, status: status)
        }
        recordResult(status: status)
    }

    private func recordResult(status: PingSnapshot.Status) {
        guard stats.transmitted > 0 else { return }
        let snapshot = PingSnapshot(
            host: host, ip: resolvedIP.isEmpty ? stats.resolvedIP : resolvedIP,
            latencyMillis: stats.avg, lossPercent: stats.lossPercent,
            jitterMillis: stats.jitter, status: status, timestamp: Date()
        )
        SharedStore.saveSnapshot(snapshot)
        SharedStore.appendHistory(CheckRecord(
            tool: "ping", host: host, timestamp: Date(),
            latencyMillis: stats.avg, lossPercent: stats.lossPercent,
            succeeded: stats.received > 0,
            detail: "\(stats.received)/\(stats.transmitted), \(Int(stats.lossPercent))% потерь, avg \(stats.avg.map { String(format: "%.0f", $0) } ?? "—") мс"
        ))
        // Samples are stored newest-first for the UI; send them chronologically.
        WebhookReporter.reportPing(stats, samples: replies.reversed())
    }

    private func resolveReverse(_ ip: String) async {
        let name = try? await ReverseDNS.lookup(ip: ip)
        await MainActor.run {
            if let name, !name.isEmpty { self.reverseName = name }
        }
    }

    func resetToDefaults() {
        probeType = .icmp
        packetSize = 56
        continuous = false
        count = 10
        interval = 1.0
        timeout = 2.0
        ttl = 64
        dontFragment = false
        reverseDNS = true
        tcpPort = 443
    }
}
