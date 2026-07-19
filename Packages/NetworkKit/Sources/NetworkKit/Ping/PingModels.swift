import Foundation

/// Configuration for a ping run.
public struct PingConfig: Sendable, Hashable, Codable {
    /// Number of echo requests to send. `nil` means continuous until cancelled.
    public var count: Int?
    /// Delay between successive requests.
    public var interval: TimeInterval
    /// Per-request timeout.
    public var timeout: TimeInterval
    /// ICMP payload size in bytes (classic default is 56, yielding a 64-byte packet).
    public var payloadSize: Int
    /// Optional TTL / hop limit to set on the socket.
    public var ttl: Int?
    /// Set the "don't fragment" bit (IPv4 only).
    public var dontFragment: Bool
    /// Prefer a specific address family. `nil` resolves both, IPv4 first.
    public var family: IPFamily?

    public init(
        count: Int? = 10,
        interval: TimeInterval = 1.0,
        timeout: TimeInterval = 2.0,
        payloadSize: Int = 56,
        ttl: Int? = nil,
        dontFragment: Bool = false,
        family: IPFamily? = nil
    ) {
        self.count = count
        self.interval = interval
        self.timeout = timeout
        self.payloadSize = max(0, min(payloadSize, 65_500))
        self.ttl = ttl
        self.dontFragment = dontFragment
        self.family = family
    }

    public static let `default` = PingConfig()
}

/// A single successful echo reply.
public struct PingReply: Sendable, Hashable, Codable {
    public let sequence: Int
    public let bytes: Int
    public let ttl: Int?
    /// Round-trip time in milliseconds.
    public let rttMillis: Double
    public let sourceIP: String

    public init(sequence: Int, bytes: Int, ttl: Int?, rttMillis: Double, sourceIP: String) {
        self.sequence = sequence
        self.bytes = bytes
        self.ttl = ttl
        self.rttMillis = rttMillis
        self.sourceIP = sourceIP
    }
}

/// Events streamed during a ping run.
public enum PingEvent: Sendable {
    /// Emitted once the host is resolved and the run begins.
    case started(resolvedIP: String, family: IPFamily)
    case reply(PingReply)
    case timeout(sequence: Int)
    /// A non-fatal ICMP error for a specific probe (e.g. host unreachable).
    case icmpError(sequence: Int, message: String)
    /// A fatal error that prevented the run (resolution/socket failure). Terminal.
    case failed(String)
    /// The run finished (all packets sent or cancelled); carries final stats.
    case finished(PingStatistics)
}

/// Aggregate statistics for a ping run.
public struct PingStatistics: Sendable, Hashable, Codable {
    public var host: String
    public var resolvedIP: String
    public var transmitted: Int
    public var received: Int
    public var rttSamples: [Double]

    public init(host: String, resolvedIP: String, transmitted: Int = 0, received: Int = 0, rttSamples: [Double] = []) {
        self.host = host
        self.resolvedIP = resolvedIP
        self.transmitted = transmitted
        self.received = received
        self.rttSamples = rttSamples
    }

    public var lossFraction: Double {
        guard transmitted > 0 else { return 0 }
        return Double(transmitted - received) / Double(transmitted)
    }
    public var lossPercent: Double { lossFraction * 100 }

    public var min: Double? { rttSamples.min() }
    public var max: Double? { rttSamples.max() }
    public var avg: Double? {
        guard !rttSamples.isEmpty else { return nil }
        return rttSamples.reduce(0, +) / Double(rttSamples.count)
    }
    /// Standard deviation of RTT samples.
    public var stddev: Double? {
        guard rttSamples.count > 1, let mean = avg else { return nil }
        let variance = rttSamples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(rttSamples.count)
        return variance.squareRoot()
    }
    /// Mean absolute consecutive difference — the common "jitter" definition (RFC 3550-ish).
    public var jitter: Double? {
        guard rttSamples.count > 1 else { return nil }
        var total = 0.0
        for i in 1..<rttSamples.count {
            total += Swift.abs(rttSamples[i] - rttSamples[i - 1])
        }
        return total / Double(rttSamples.count - 1)
    }
}
