import Foundation

public struct TracerouteProbe: Sendable, Hashable, Codable {
    public let rttMillis: Double?
    public let routerIP: String?
    public var responded: Bool { rttMillis != nil }
}

public struct TracerouteHop: Sendable, Hashable, Codable, Identifiable {
    public var id: Int { ttl }
    public let ttl: Int
    public let probes: [TracerouteProbe]
    public let reachedDestination: Bool
    public var hostname: String?

    /// The first router IP that answered this hop, if any.
    public var routerIP: String? {
        probes.compactMap { $0.routerIP }.first
    }
    public var isTimeout: Bool { routerIP == nil }
    /// Best (minimum) RTT across probes.
    public var bestRTT: Double? {
        probes.compactMap { $0.rttMillis }.min()
    }
}

public struct TracerouteConfig: Sendable, Hashable, Codable {
    public var maxHops: Int
    public var probesPerHop: Int
    public var timeout: TimeInterval
    public var resolveNames: Bool
    public var family: IPFamily?

    public init(maxHops: Int = 30, probesPerHop: Int = 3, timeout: TimeInterval = 2.0,
                resolveNames: Bool = true, family: IPFamily? = nil) {
        self.maxHops = max(1, min(maxHops, 64))
        self.probesPerHop = max(1, min(probesPerHop, 5))
        self.timeout = timeout
        self.resolveNames = resolveNames
        self.family = family
    }
    public static let `default` = TracerouteConfig()
}

public enum TracerouteEvent: Sendable {
    case started(resolvedIP: String, family: IPFamily)
    case hop(TracerouteHop)
    case finished(reached: Bool)
}

/// TTL-limited ICMP traceroute. Sends echo requests with increasing TTL and
/// records the routers that return ICMP Time-Exceeded, stopping at the target.
public final class Traceroute: Sendable {
    public init() {}

    public func trace(host: String, config: TracerouteConfig = .default) -> AsyncStream<TracerouteEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let runner = TraceRunner(host: host, config: config, continuation: continuation)
            continuation.onTermination = { _ in runner.cancel() }
            runner.start()
        }
    }
}

private final class TraceRunner: @unchecked Sendable {
    private let host: String
    private let config: TracerouteConfig
    private let continuation: AsyncStream<TracerouteEvent>.Continuation
    private let queue = DispatchQueue(label: "networkkit.traceroute", qos: .userInitiated)
    private let lock = NSLock()
    private var cancelled = false
    private var fd: Int32 = -1
    private let identifier = UInt16.random(in: 1...UInt16.max)

    init(host: String, config: TracerouteConfig, continuation: AsyncStream<TracerouteEvent>.Continuation) {
        self.host = host
        self.config = config
        self.continuation = continuation
    }

    func cancel() {
        lock.lock(); cancelled = true; let f = fd; fd = -1; lock.unlock()
        if f >= 0 { close(f) }
    }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    func start() {
        Task {
            do {
                let endpoint = try await HostResolver.resolveFirst(host: host, family: config.family)
                queue.async { [self] in run(endpoint: endpoint) }
            } catch {
                continuation.finish()
            }
        }
    }

    private func run(endpoint: ResolvedEndpoint) {
        let make = SocketFactory.makeICMP(endpoint: endpoint, config: PingConfig(count: 1))
        guard case .success(let f) = make else { continuation.finish(); return }
        lock.lock(); fd = f; lock.unlock()

        continuation.yield(.started(resolvedIP: endpoint.ipString, family: endpoint.family))

        var seqCounter: UInt16 = 0
        var reached = false

        for ttl in 1...config.maxHops {
            if isCancelled { break }
            SocketFactory.setTTL(fd: f, family: endpoint.family, ttl: ttl)

            var probes: [TracerouteProbe] = []
            var hopReached = false
            var routerForHop: String?

            for _ in 0..<config.probesPerHop {
                if isCancelled { break }
                seqCounter &+= 1
                let probe = sendProbe(fd: f, endpoint: endpoint, seq: seqCounter)
                probes.append(probe.probe)
                if let ip = probe.probe.routerIP { routerForHop = routerForHop ?? ip }
                if probe.reachedDestination { hopReached = true }
            }

            var hostname: String?
            if config.resolveNames, let ip = routerForHop {
                hostname = reverseLookupSync(ip)
            }

            let hop = TracerouteHop(ttl: ttl, probes: probes, reachedDestination: hopReached, hostname: hostname)
            continuation.yield(.hop(hop))

            if hopReached { reached = true; break }
        }

        lock.lock(); let f2 = fd; fd = -1; lock.unlock()
        if f2 >= 0 { close(f2) }
        continuation.yield(.finished(reached: reached))
        continuation.finish()
    }

    /// Sends one probe and waits up to timeout for a matching reply.
    private func sendProbe(fd: Int32, endpoint: ResolvedEndpoint, seq: UInt16) -> (probe: TracerouteProbe, reachedDestination: Bool) {
        let payload = [UInt8]("CheckNetTR".utf8)
        let packet = ICMP.echoRequest(family: endpoint.family, identifier: identifier, sequence: seq, payload: payload)
        let sendTime = MonoClock.nanos()
        let sent = endpoint.withSockaddr { addr, len in
            packet.withUnsafeBytes { raw in sendto(fd, raw.baseAddress, raw.count, 0, addr, len) }
        }
        guard sent >= 0 else { return (TracerouteProbe(rttMillis: nil, routerIP: nil), false) }

        let deadline = sendTime + UInt64(config.timeout * 1_000_000_000)
        while MonoClock.nanos() < deadline {
            if isCancelled { break }
            let remaining = deadline > MonoClock.nanos() ? deadline - MonoClock.nanos() : 0
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let pr = poll(&pfd, 1, Int32(min(1000, remaining / 1_000_000)))
            if pr <= 0 { continue }
            guard let received = SocketFactory.receive(fd: fd, family: endpoint.family),
                  let parsed = ICMP.parseReply(received.data, family: endpoint.family) else { continue }
            switch parsed.kind {
            case .echoReply where parsed.sequence == seq:
                let rtt = Double(MonoClock.nanos() &- sendTime) / 1_000_000.0
                return (TracerouteProbe(rttMillis: rtt, routerIP: received.sourceIP ?? endpoint.ipString), true)
            case .timeExceeded where parsed.sequence == seq:
                let rtt = Double(MonoClock.nanos() &- sendTime) / 1_000_000.0
                return (TracerouteProbe(rttMillis: rtt, routerIP: received.sourceIP), false)
            case .unreachable where parsed.sequence == seq:
                let rtt = Double(MonoClock.nanos() &- sendTime) / 1_000_000.0
                // Destination or an intermediate returned unreachable; treat as a
                // responding hop but not a successful arrival.
                return (TracerouteProbe(rttMillis: rtt, routerIP: received.sourceIP), received.sourceIP == endpoint.ipString)
            default:
                continue
            }
        }
        return (TracerouteProbe(rttMillis: nil, routerIP: nil), false)
    }

    private func reverseLookupSync(_ ip: String) -> String? {
        var hints = addrinfo()
        hints.ai_flags = AI_NUMERICHOST
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(ip, nil, &hints, &info) == 0, let node = info else { return nil }
        defer { freeaddrinfo(info) }
        var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(node.pointee.ai_addr, node.pointee.ai_addrlen,
                          &hostBuf, socklen_t(hostBuf.count), nil, 0, NI_NAMEREQD) == 0 else { return nil }
        let name = String(nullTerminated: hostBuf)
        return name == ip ? nil : name
    }
}
