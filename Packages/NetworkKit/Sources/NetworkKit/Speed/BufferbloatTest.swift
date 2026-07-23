import Foundation

/// Bufferbloat: how much latency the link adds when it is saturated.
///
/// A fast connection can still make video calls and games stutter if its
/// buffers swell under load — packets queue instead of dropping, and round-trip
/// time balloons. We measure it the way Waveform/DSLReports do: sample RTT while
/// idle, then again while saturating download and upload, and grade the increase
/// A–F. Detection only — we report the number, we don't try to fix the queue.
public struct BufferbloatTest: Sendable {
    public init() {}

    public struct Config: Sendable {
        /// Where the latency probe pings. An IP literal avoids per-ping DNS.
        public var latencyHost: String
        public var idleSeconds: TimeInterval
        /// Load duration per direction (download, then upload).
        public var loadSeconds: TimeInterval
        public var pingInterval: TimeInterval
        public var pingTimeout: TimeInterval
        /// Parallel HTTP streams used to fill the pipe.
        public var streams: Int

        public init(latencyHost: String = "1.1.1.1", idleSeconds: TimeInterval = 3,
                    loadSeconds: TimeInterval = 6, pingInterval: TimeInterval = 0.2,
                    pingTimeout: TimeInterval = 2, streams: Int = 4) {
            self.latencyHost = latencyHost
            self.idleSeconds = idleSeconds
            self.loadSeconds = loadSeconds
            self.pingInterval = pingInterval
            self.pingTimeout = pingTimeout
            self.streams = streams
        }
    }

    // MARK: Run

    public func run(config: Config = Config()) -> AsyncStream<BufferbloatEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task { await execute(config: config, continuation: continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func execute(config: Config, continuation: AsyncStream<BufferbloatEvent>.Continuation) async {
        let start = MonoClock.nanos()
        func elapsed() -> TimeInterval { Double(MonoClock.nanos() &- start) / 1_000_000_000 }

        // Idle baseline.
        continuation.yield(.phase(.idle))
        let idle = await pingLoop(phase: .idle, seconds: config.idleSeconds, config: config,
                                  startNanos: start, continuation: continuation)
        guard !idle.isEmpty else {
            continuation.yield(.failed("Хост \(config.latencyHost) не отвечает на пинг — не с чем сравнивать."))
            continuation.finish()
            return
        }
        guard !Task.isCancelled else { continuation.finish(); return }

        // Download under load.
        continuation.yield(.phase(.download))
        async let downMbps = Self.generateLoad(direction: .download, seconds: config.loadSeconds, streams: config.streams)
        let down = await pingLoop(phase: .download, seconds: config.loadSeconds, config: config,
                                  startNanos: start, continuation: continuation)
        let downloadMbps = await downMbps
        guard !Task.isCancelled else { continuation.finish(); return }

        // Upload under load.
        continuation.yield(.phase(.upload))
        async let upMbps = Self.generateLoad(direction: .upload, seconds: config.loadSeconds, streams: config.streams)
        let up = await pingLoop(phase: .upload, seconds: config.loadSeconds, config: config,
                                startNanos: start, continuation: continuation)
        let uploadMbps = await upMbps

        let result = Self.summarise(idle: idle, download: down, upload: up,
                                    downloadMbps: downloadMbps, uploadMbps: uploadMbps,
                                    samples: sampleLog)
        continuation.yield(.finished(result))
        continuation.finish()
    }

    // MARK: Probe

    /// A running log of every sample yielded, so the finished result carries the
    /// full graph. Collected on the single execute() task, so no synchronisation.
    private var sampleLog: [BufferbloatSample] { _sampleLog.value }
    private let _sampleLog = SampleBox()

    private func pingLoop(phase: BufferbloatPhase, seconds: TimeInterval, config: Config,
                          startNanos: UInt64,
                          continuation: AsyncStream<BufferbloatEvent>.Continuation) async -> [Double] {
        var rtts: [Double] = []
        let deadline = MonoClock.nanos() &+ UInt64(seconds * 1_000_000_000)
        while MonoClock.nanos() < deadline, !Task.isCancelled {
            if let rtt = await Self.pingOnce(host: config.latencyHost, timeout: config.pingTimeout) {
                rtts.append(rtt)
                let sample = BufferbloatSample(
                    phase: phase,
                    elapsed: Double(MonoClock.nanos() &- startNanos) / 1_000_000_000,
                    rttMillis: rtt
                )
                _sampleLog.append(sample)
                continuation.yield(.sample(sample))
            }
            try? await Task.sleep(for: .seconds(config.pingInterval))
        }
        return rtts
    }

    static func pingOnce(host: String, timeout: TimeInterval) async -> Double? {
        let config = PingConfig(count: 1, interval: 0, timeout: timeout)
        guard let stats = try? await ICMPPinger().measure(host: host, config: config),
              stats.received > 0, let avg = stats.avg else { return nil }
        return avg
    }

    // MARK: Load generation

    /// Saturate one direction with `streams` parallel HTTP transfers for
    /// `seconds`; returns the aggregate throughput in Mbps.
    static func generateLoad(direction: SpeedDirection, seconds: TimeInterval, streams: Int) async -> Double {
        let start = MonoClock.nanos()
        let total = await withTaskGroup(of: Int.self) { group -> Int in
            for _ in 0..<Swift.max(1, streams) {
                group.addTask { await oneStream(direction: direction, seconds: seconds) }
            }
            var sum = 0
            for await bytes in group { sum += bytes }
            return sum
        }
        let elapsed = Swift.max(Double(MonoClock.nanos() &- start) / 1_000_000_000, 0.001)
        return Double(total) * 8 / elapsed / 1_000_000
    }

    private static func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.timeoutIntervalForRequest = 30
        return URLSession(configuration: cfg)
    }

    private static func oneStream(direction: SpeedDirection, seconds: TimeInterval) async -> Int {
        let session = session()
        let deadline = MonoClock.nanos() &+ UInt64(seconds * 1_000_000_000)
        var bytes = 0
        while MonoClock.nanos() < deadline, !Task.isCancelled {
            let remaining = Double(deadline &- MonoClock.nanos()) / 1_000_000_000
            if remaining < 0.1 { break }
            let got = await boundedTransfer(direction: direction, session: session, maxSeconds: remaining)
            bytes += got
            if got == 0 { break }   // cut short by the phase deadline, or failed
        }
        return bytes
    }

    /// One 10 MB HTTP transfer, abandoned if it would outlast `maxSeconds` — so a
    /// slow link can't stretch a phase far past its budget (a 100 MB chunk over a
    /// 3 Mbps link is ~4 minutes). A transfer cut short reports 0 bytes: its
    /// throughput is unknown, but the load was real while it ran, which is what
    /// the concurrent ping needs.
    private static func boundedTransfer(direction: SpeedDirection, session: URLSession,
                                        maxSeconds: TimeInterval) async -> Int {
        await withTaskGroup(of: Int.self) { group in
            group.addTask {
                switch direction {
                case .download:
                    guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=10000000"),
                          let (data, _) = try? await session.data(from: url) else { return 0 }
                    return data.count
                case .upload:
                    guard let url = URL(string: "https://speed.cloudflare.com/__up") else { return 0 }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    let payload = Data(count: 10_000_000)
                    guard (try? await session.upload(for: request, from: payload)) != nil else { return 0 }
                    return payload.count
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(maxSeconds))
                return -1
            }
            let first = await group.next() ?? -1
            group.cancelAll()
            return Swift.max(0, first)
        }
    }

    // MARK: Summary (pure)

    static func summarise(idle: [Double], download: [Double], upload: [Double],
                          downloadMbps: Double?, uploadMbps: Double?,
                          samples: [BufferbloatSample]) -> BufferbloatResult {
        let idleRTT = median(idle)
        // A saturated phase with no replies means every probe timed out — the
        // worst bufferbloat there is, not a missing measurement. Fall back to the
        // ping timeout so it grades as F rather than vanishing.
        let downRTT = download.isEmpty ? idleRTT + 500 : median(download)
        let upRTT = upload.isEmpty ? idleRTT + 500 : median(upload)
        let added = Swift.max(0, Swift.max(downRTT, upRTT) - idleRTT)
        return BufferbloatResult(
            idleRTT: idleRTT,
            downloadRTT: downRTT,
            uploadRTT: upRTT,
            idleJitter: jitter(idle),
            downloadMbps: downloadMbps,
            uploadMbps: uploadMbps,
            addedLatency: added,
            grade: BufferbloatGrade.grade(addedLatencyMillis: added),
            samples: samples
        )
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    static func jitter(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<values.count { total += Swift.abs(values[i] - values[i - 1]) }
        return total / Double(values.count - 1)
    }
}

// MARK: - Models

public enum BufferbloatPhase: String, Sendable, Codable, Hashable {
    case idle, download, upload
}

public struct BufferbloatSample: Sendable, Codable, Hashable {
    public let phase: BufferbloatPhase
    /// Seconds since the test started, for the timeline graph.
    public let elapsed: TimeInterval
    public let rttMillis: Double

    public init(phase: BufferbloatPhase, elapsed: TimeInterval, rttMillis: Double) {
        self.phase = phase
        self.elapsed = elapsed
        self.rttMillis = rttMillis
    }
}

/// A–F, graded on the latency a saturated link adds over its idle RTT. Anchored
/// like Waveform/DSLReports: A ≈ imperceptible, F ≈ calls and games break.
public enum BufferbloatGrade: String, Sendable, Codable, Hashable, CaseIterable {
    case a, b, c, d, f

    public var letter: String { rawValue.uppercased() }

    /// Added latency thresholds (ms): A < 5, B < 30, C < 100, D < 400, F ≥ 400.
    public static func grade(addedLatencyMillis ms: Double) -> BufferbloatGrade {
        switch ms {
        case ..<5:   return .a
        case ..<30:  return .b
        case ..<100: return .c
        case ..<400: return .d
        default:     return .f
        }
    }
}

public struct BufferbloatResult: Sendable, Codable, Hashable {
    public let idleRTT: Double
    public let downloadRTT: Double
    public let uploadRTT: Double
    public let idleJitter: Double
    public let downloadMbps: Double?
    public let uploadMbps: Double?
    /// max(downloadRTT, uploadRTT) − idleRTT, clamped at 0.
    public let addedLatency: Double
    public let grade: BufferbloatGrade
    public let samples: [BufferbloatSample]
}

public enum BufferbloatEvent: Sendable {
    case phase(BufferbloatPhase)
    case sample(BufferbloatSample)
    case finished(BufferbloatResult)
    case failed(String)
}

/// Collects samples on the single execute() task. Not shared across tasks, but
/// boxed so the struct's methods can append without being `mutating`.
private final class SampleBox: @unchecked Sendable {
    private var samples: [BufferbloatSample] = []
    var value: [BufferbloatSample] { samples }
    func append(_ sample: BufferbloatSample) { samples.append(sample) }
}
