import Foundation

public struct MTRHop: Sendable, Hashable, Codable, Identifiable {
    public var id: Int { ttl }
    public let ttl: Int
    public var host: String?
    public var hostname: String?
    public var sent: Int
    public var received: Int
    public var last: Double?
    public var best: Double?
    public var worst: Double?
    public var total: Double   // sum for average
    public var reachedDestination: Bool

    public var lossPercent: Double {
        guard sent > 0 else { return 0 }
        return Double(sent - received) / Double(sent) * 100
    }
    public var average: Double? {
        guard received > 0 else { return nil }
        return total / Double(received)
    }
}

public struct MTRConfig: Sendable {
    public var maxHops: Int
    public var timeout: TimeInterval
    public var interval: TimeInterval
    public var maxRounds: Int?  // nil = until cancelled
    public var resolveNames: Bool
    public init(maxHops: Int = 30, timeout: TimeInterval = 1.5, interval: TimeInterval = 1.0,
                maxRounds: Int? = nil, resolveNames: Bool = true) {
        self.maxHops = maxHops
        self.timeout = timeout
        self.interval = interval
        self.maxRounds = maxRounds
        self.resolveNames = resolveNames
    }
}

public enum MTREvent: Sendable {
    case started(resolvedIP: String)
    case update(hops: [MTRHop], round: Int)
    case finished
}

/// Continuous traceroute + ping ("my traceroute"): every round probes each hop
/// once and accumulates per-hop loss / best / worst / average.
public final class MTRSession: Sendable {
    public init() {}

    public func run(host: String, config: MTRConfig = MTRConfig()) -> AsyncStream<MTREvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let runner = MTRRunner(host: host, config: config, continuation: continuation)
            continuation.onTermination = { _ in runner.cancel() }
            runner.start()
        }
    }
}

private final class MTRRunner: @unchecked Sendable {
    private let host: String
    private let config: MTRConfig
    private let continuation: AsyncStream<MTREvent>.Continuation
    private let queue = DispatchQueue(label: "networkkit.mtr", qos: .userInitiated)
    private let lock = NSLock()
    private var cancelled = false
    private var fd: Int32 = -1
    private let identifier = UInt16.random(in: 1...UInt16.max)

    init(host: String, config: MTRConfig, continuation: AsyncStream<MTREvent>.Continuation) {
        self.host = host; self.config = config; self.continuation = continuation
    }

    func cancel() {
        lock.lock(); cancelled = true; let f = fd; fd = -1; lock.unlock()
        if f >= 0 { close(f) }
    }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    func start() {
        Task {
            do {
                let endpoint = try await HostResolver.resolveFirst(host: host, family: .ipv4)
                queue.async { [self] in run(endpoint: endpoint) }
            } catch { continuation.finish() }
        }
    }

    private func run(endpoint: ResolvedEndpoint) {
        guard case .success(let f) = SocketFactory.makeICMP(endpoint: endpoint, config: PingConfig(count: 1)) else {
            continuation.finish(); return
        }
        lock.lock(); fd = f; lock.unlock()
        continuation.yield(.started(resolvedIP: endpoint.ipString))

        var hops: [Int: MTRHop] = [:]
        var activeMax = config.maxHops
        var seqCounter: UInt16 = 0
        var round = 0

        // WinMTR model: every cycle fires one probe at each TTL up front, then
        // collects all replies within a single shared timeout window — so a cycle
        // takes ~timeout, not maxHops × timeout. Per-hop stats accumulate over rounds.
        while !isCancelled {
            round += 1
            var pending: [UInt16: (ttl: Int, time: UInt64)] = [:]
            let cycleStart = MonoClock.nanos()

            for ttl in 1...activeMax {
                if isCancelled { break }
                SocketFactory.setTTL(fd: f, family: endpoint.family, ttl: ttl)
                seqCounter &+= 1
                let seq = seqCounter
                let packet = ICMP.echoRequest(family: endpoint.family, identifier: identifier,
                                              sequence: seq, payload: [UInt8]("MTR".utf8))
                let now = MonoClock.nanos()
                _ = endpoint.withSockaddr { addr, len in
                    packet.withUnsafeBytes { raw in sendto(f, raw.baseAddress, raw.count, 0, addr, len) }
                }
                pending[seq] = (ttl, now)
                var hop = hops[ttl] ?? MTRHop(ttl: ttl, host: nil, hostname: nil, sent: 0, received: 0,
                                              last: nil, best: nil, worst: nil, total: 0, reachedDestination: false)
                hop.sent += 1
                hops[ttl] = hop
            }

            // Collect replies until the shared window elapses.
            let deadline = cycleStart + UInt64(config.timeout * 1_000_000_000)
            var destinationTTL: Int? = nil
            while !pending.isEmpty && !isCancelled {
                let nowNanos = MonoClock.nanos()
                guard nowNanos < deadline else { break }
                let remaining = deadline - nowNanos
                var pfd = pollfd(fd: f, events: Int16(POLLIN), revents: 0)
                if poll(&pfd, 1, Int32(min(500, remaining / 1_000_000))) <= 0 { continue }
                guard let received = SocketFactory.receive(fd: f, family: endpoint.family),
                      let parsed = ICMP.parseReply(received.data, family: endpoint.family),
                      parsed.identifier == identifier,
                      let info = pending[parsed.sequence] else { continue }
                pending[parsed.sequence] = nil
                let ttl = info.ttl
                let rtt = Double(MonoClock.nanos() &- info.time) / 1_000_000.0
                var hop = hops[ttl] ?? MTRHop(ttl: ttl, host: nil, hostname: nil, sent: 1, received: 0,
                                              last: nil, best: nil, worst: nil, total: 0, reachedDestination: false)
                switch parsed.kind {
                case .echoReply, .timeExceeded, .unreachable:
                    hop.received += 1
                    hop.last = rtt
                    hop.best = min(hop.best ?? rtt, rtt)
                    hop.worst = max(hop.worst ?? rtt, rtt)
                    hop.total += rtt
                    if let ip = received.sourceIP { hop.host = ip }
                    let reached = parsed.kind == .echoReply
                        || (parsed.kind == .unreachable && received.sourceIP == endpoint.ipString)
                    if reached { hop.reachedDestination = true; destinationTTL = min(destinationTTL ?? ttl, ttl) }
                case .other:
                    break
                }
                hops[ttl] = hop
            }

            // Once the destination answers, freeze the hop count there.
            if let d = destinationTTL { activeMax = min(activeMax, d) }

            continuation.yield(.update(hops: (1...activeMax).compactMap { hops[$0] }, round: round))

            // Resolve router names lazily (cached once found), then push an enriched snapshot.
            if config.resolveNames {
                var changed = false
                for ttl in 1...activeMax {
                    if var hop = hops[ttl], hop.hostname == nil, let ip = hop.host {
                        hop.hostname = reverseLookup(ip)
                        hops[ttl] = hop
                        changed = changed || hop.hostname != nil
                    }
                }
                if changed {
                    continuation.yield(.update(hops: (1...activeMax).compactMap { hops[$0] }, round: round))
                }
            }

            if let maxRounds = config.maxRounds, round >= maxRounds { break }
            if isCancelled { break }
            Thread.sleep(forTimeInterval: config.interval)
        }

        lock.lock(); let f2 = fd; fd = -1; lock.unlock()
        if f2 >= 0 { close(f2) }
        continuation.yield(.finished)
        continuation.finish()
    }

    private func reverseLookup(_ ip: String) -> String? {
        var hints = addrinfo(); hints.ai_flags = AI_NUMERICHOST
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(ip, nil, &hints, &info) == 0, let node = info else { return nil }
        defer { freeaddrinfo(info) }
        var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(node.pointee.ai_addr, node.pointee.ai_addrlen, &buf, socklen_t(buf.count), nil, 0, NI_NAMEREQD) == 0 else { return nil }
        let name = String(cString: buf)
        return name == ip ? nil : name
    }
}
