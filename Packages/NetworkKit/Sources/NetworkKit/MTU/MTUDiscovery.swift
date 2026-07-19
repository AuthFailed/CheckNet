import Foundation

public struct MTUResult: Sendable, Hashable, Codable {
    public let host: String
    public let resolvedIP: String
    /// Largest ICMP payload that traversed the path without fragmentation.
    public let maxPayload: Int
    /// Effective path MTU = payload + IPv4(20) + ICMP(8).
    public let pathMTU: Int
    public let probes: [MTUProbe]

    public struct MTUProbe: Sendable, Hashable, Codable {
        public let payload: Int
        public let succeeded: Bool
    }
}

public enum MTUProgress: Sendable {
    case probing(payload: Int)
    case finished(MTUResult)
    case failed(String)
}

/// Discovers the path MTU by binary-searching the largest ICMP echo payload
/// that survives with the "don't fragment" bit set.
public final class MTUDiscovery: Sendable {
    public init() {}

    private static let ipICMPOverhead = 28  // IPv4 header (20) + ICMP header (8)

    public func discover(
        host: String,
        low: Int = 0,
        high: Int = 1472,   // 1500 MTU - 28
        perProbeTimeout: TimeInterval = 1.0
    ) -> AsyncStream<MTUProgress> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    let endpoint = try await HostResolver.resolveFirst(host: host, family: .ipv4)
                    var probes: [MTUResult.MTUProbe] = []

                    // Ensure the smallest size works at all (host reachable).
                    continuation.yield(.probing(payload: low))
                    guard await probe(host: host, size: low, timeout: perProbeTimeout) else {
                        continuation.yield(.failed("Хост не отвечает на ICMP"))
                        continuation.finish()
                        return
                    }
                    probes.append(.init(payload: low, succeeded: true))

                    var lo = low
                    var hi = high
                    var best = low
                    // Binary search for the largest payload that still gets a reply.
                    while lo <= hi {
                        if Task.isCancelled { break }
                        let mid = (lo + hi) / 2
                        continuation.yield(.probing(payload: mid))
                        let ok = await probe(host: host, size: mid, timeout: perProbeTimeout)
                        probes.append(.init(payload: mid, succeeded: ok))
                        if ok {
                            best = mid
                            lo = mid + 1
                        } else {
                            hi = mid - 1
                        }
                    }

                    let result = MTUResult(
                        host: host, resolvedIP: endpoint.ipString,
                        maxPayload: best, pathMTU: best + Self.ipICMPOverhead,
                        probes: probes
                    )
                    continuation.yield(.finished(result))
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Sends up to two DF pings of `size` bytes; success if any reply returns.
    private func probe(host: String, size: Int, timeout: TimeInterval) async -> Bool {
        let config = PingConfig(count: 2, interval: 0.15, timeout: timeout,
                                payloadSize: size, dontFragment: true, family: .ipv4)
        let pinger = ICMPPinger()
        for await event in pinger.ping(host: host, config: config) {
            if case .reply = event { return true }
        }
        return false
    }
}
