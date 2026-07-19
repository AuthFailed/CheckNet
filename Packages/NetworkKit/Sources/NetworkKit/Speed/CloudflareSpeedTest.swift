import Foundation

/// A dependency-free HTTP speed test against Cloudflare's public endpoints,
/// used as a fallback when no iperf3 server is reachable.
public final class CloudflareSpeedTest: Sendable {
    public init() {}

    public func run(duration: TimeInterval = 10, download: Bool = true, upload: Bool = true) -> AsyncStream<SpeedEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                var result = SpeedResult(downloadMbps: nil, uploadMbps: nil, server: "speed.cloudflare.com", latencyMillis: nil)
                if let latency = await Self.latency() { result.latencyMillis = latency }
                if download {
                    continuation.yield(.phase("Загрузка (download)…"))
                    result.downloadMbps = await Self.measureDownload(seconds: duration / 2, continuation: continuation)
                }
                if upload && !Task.isCancelled {
                    continuation.yield(.phase("Отдача (upload)…"))
                    result.uploadMbps = await Self.measureUpload(seconds: duration / 2, continuation: continuation)
                }
                continuation.yield(.finished(result))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.timeoutIntervalForRequest = 30
        return URLSession(configuration: cfg)
    }

    static func latency() async -> Double? {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=0") else { return nil }
        let start = MonoClock.nanos()
        guard (try? await session().data(from: url)) != nil else { return nil }
        return MonoClock.millisSince(start)
    }

    static func measureDownload(seconds: TimeInterval, continuation: AsyncStream<SpeedEvent>.Continuation) async -> Double {
        let deadline = MonoClock.nanos() + UInt64(seconds * 1_000_000_000)
        let start = MonoClock.nanos()
        var totalBytes = 0
        var chunk = 25_000_000  // ramp per request
        while MonoClock.nanos() < deadline && !Task.isCancelled {
            guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(chunk)") else { break }
            guard let (data, _) = try? await session().data(from: url) else { break }
            totalBytes += data.count
            let elapsed = Double(MonoClock.nanos() - start) / 1_000_000_000
            let mbps = elapsed > 0 ? Double(totalBytes) * 8 / elapsed / 1_000_000 : 0
            continuation.yield(.sample(SpeedSample(seconds: elapsed, mbps: mbps, direction: .download)))
            chunk = min(chunk * 2, 100_000_000)
        }
        let elapsed = max(Double(MonoClock.nanos() - start) / 1_000_000_000, 0.001)
        return Double(totalBytes) * 8 / elapsed / 1_000_000
    }

    static func measureUpload(seconds: TimeInterval, continuation: AsyncStream<SpeedEvent>.Continuation) async -> Double {
        let deadline = MonoClock.nanos() + UInt64(seconds * 1_000_000_000)
        let start = MonoClock.nanos()
        var totalBytes = 0
        let payload = Data(count: 10_000_000)
        while MonoClock.nanos() < deadline && !Task.isCancelled {
            guard let url = URL(string: "https://speed.cloudflare.com/__up") else { break }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            guard (try? await session().upload(for: request, from: payload)) != nil else { break }
            totalBytes += payload.count
            let elapsed = Double(MonoClock.nanos() - start) / 1_000_000_000
            let mbps = elapsed > 0 ? Double(totalBytes) * 8 / elapsed / 1_000_000 : 0
            continuation.yield(.sample(SpeedSample(seconds: elapsed, mbps: mbps, direction: .upload)))
        }
        let elapsed = max(Double(MonoClock.nanos() - start) / 1_000_000_000, 0.001)
        return Double(totalBytes) * 8 / elapsed / 1_000_000
    }
}
