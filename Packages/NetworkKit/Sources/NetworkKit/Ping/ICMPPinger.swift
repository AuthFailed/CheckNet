import Foundation

/// Sends ICMP echo requests using an unprivileged `SOCK_DGRAM` ICMP socket
/// (works on iOS and macOS without root) and streams replies/timeouts.
public final class ICMPPinger: Sendable {
    public init() {}

    /// Streams ping events for `host`. The run stops when `config.count` probes
    /// have been sent and resolved, or when the surrounding Task is cancelled.
    public func ping(host: String, config: PingConfig = .default) -> AsyncStream<PingEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let runner = PingRunner(host: host, config: config, continuation: continuation)
            continuation.onTermination = { _ in runner.cancel() }
            runner.start()
        }
    }

    /// Convenience: run a bounded ping and return aggregate statistics.
    public func measure(host: String, config: PingConfig = .default) async throws -> PingStatistics {
        var stats: PingStatistics?
        for await event in ping(host: host, config: config) {
            if case .finished(let s) = event { stats = s }
        }
        guard let stats else { throw NetworkError.cancelled }
        return stats
    }
}

/// Owns one ping run: the socket, the send/receive event loop, and cancellation.
private final class PingRunner: @unchecked Sendable {
    private let host: String
    private let config: PingConfig
    private let continuation: AsyncStream<PingEvent>.Continuation
    private let queue = DispatchQueue(label: "networkkit.ping", qos: .userInitiated)

    private let lock = NSLock()
    private var fd: Int32 = -1
    private var cancelled = false
    private let identifier = UInt16.random(in: 1...UInt16.max)

    init(host: String, config: PingConfig, continuation: AsyncStream<PingEvent>.Continuation) {
        self.host = host
        self.config = config
        self.continuation = continuation
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let f = fd
        fd = -1
        lock.unlock()
        if f >= 0 { close(f) }
    }

    private var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func start() {
        queue.async { [self] in run() }
    }

    private func run() {
        Task {
            do {
                let endpoint = try await HostResolver.resolveFirst(host: host, family: config.family)
                queue.async { [self] in self.loop(endpoint: endpoint) }
            } catch {
                var stats = PingStatistics(host: host, resolvedIP: "")
                finish(&stats)
            }
        }
    }

    private func loop(endpoint: ResolvedEndpoint) {
        var stats = PingStatistics(host: host, resolvedIP: endpoint.ipString)

        let sock = SocketFactory.makeICMP(endpoint: endpoint, config: config)
        guard case .success(let f) = sock else {
            finish(&stats)
            return
        }
        lock.lock(); fd = f; lock.unlock()

        continuation.yield(.started(resolvedIP: endpoint.ipString, family: endpoint.family))

        var sentCount = 0
        var nextSendAt = MonoClock.nanos()
        // seq -> (sendTime nanos, deadline nanos)
        var pending: [UInt16: (send: UInt64, deadline: UInt64)] = [:]
        let intervalNanos = UInt64(config.interval * 1_000_000_000)
        let timeoutNanos = UInt64(config.timeout * 1_000_000_000)
        let payload = Self.makePayload(size: config.payloadSize)

        func moreToSend() -> Bool {
            if let c = config.count { return sentCount < c }
            return true
        }

        while !isCancelled {
            let now = MonoClock.nanos()

            // Send if a probe is due.
            if moreToSend(), now >= nextSendAt {
                let seq = UInt16(truncatingIfNeeded: sentCount)
                let packet = ICMP.echoRequest(family: endpoint.family, identifier: identifier, sequence: seq, payload: payload)
                let ok = endpoint.withSockaddr { addr, len in
                    packet.withUnsafeBytes { raw in
                        sendto(f, raw.baseAddress, raw.count, 0, addr, len)
                    }
                }
                stats.transmitted += 1
                if ok >= 0 {
                    pending[seq] = (now, now + timeoutNanos)
                } else {
                    continuation.yield(.icmpError(sequence: Int(seq), message: String(cString: strerror(errno))))
                }
                sentCount += 1
                nextSendAt = now + intervalNanos
            }

            // Termination: nothing left to send and nothing pending.
            if !moreToSend() && pending.isEmpty { break }

            // Compute how long to wait: until next send or the nearest deadline.
            var wakeAt = UInt64.max
            if moreToSend() { wakeAt = Swift.min(wakeAt, nextSendAt) }
            for (_, v) in pending { wakeAt = Swift.min(wakeAt, v.deadline) }
            let waitNanos = wakeAt == .max ? intervalNanos : (wakeAt > now ? wakeAt - now : 0)
            let waitMillis = Int32(Swift.min(1000, waitNanos / 1_000_000))

            var pfd = pollfd(fd: f, events: Int16(POLLIN), revents: 0)
            let pr = poll(&pfd, 1, Swift.max(1, waitMillis))
            if isCancelled { break }

            if pr > 0, (pfd.revents & Int16(POLLIN)) != 0 {
                while let received = SocketFactory.receive(fd: f, family: endpoint.family) {
                    guard let parsed = ICMP.parseReply(received.data, family: endpoint.family) else { continue }
                    switch parsed.kind {
                    case .echoReply:
                        guard let info = pending[parsed.sequence] else { continue }
                        let rtt = Double(MonoClock.nanos() &- info.send) / 1_000_000.0
                        pending[parsed.sequence] = nil
                        stats.received += 1
                        stats.rttSamples.append(rtt)
                        continuation.yield(.reply(PingReply(
                            sequence: Int(parsed.sequence),
                            bytes: received.data.count,
                            ttl: received.ttl,
                            rttMillis: rtt,
                            sourceIP: received.sourceIP ?? endpoint.ipString
                        )))
                    case .unreachable:
                        if pending[parsed.sequence] != nil {
                            pending[parsed.sequence] = nil
                            continuation.yield(.icmpError(sequence: Int(parsed.sequence), message: "Host unreachable"))
                        }
                    case .timeExceeded, .other:
                        continue
                    }
                }
            }

            // Expire timed-out probes.
            let checkNow = MonoClock.nanos()
            for (seq, v) in pending where checkNow >= v.deadline {
                pending[seq] = nil
                continuation.yield(.timeout(sequence: Int(seq)))
            }
        }

        finish(&stats)
    }

    private func finish(_ stats: inout PingStatistics) {
        lock.lock()
        let f = fd
        fd = -1
        lock.unlock()
        if f >= 0 { close(f) }
        continuation.yield(.finished(stats))
        continuation.finish()
    }

    private static func makePayload(size: Int) -> [UInt8] {
        guard size > 0 else { return [] }
        var payload = [UInt8](repeating: 0, count: size)
        // Fill with a recognizable ascending pattern (like classic ping).
        for i in 0..<size { payload[i] = UInt8(truncatingIfNeeded: i) }
        return payload
    }
}
