import Foundation

/// Utilities for parsing and enumerating IPv4 ranges (CIDR, dash range, or /24 base).
public enum IPv4Range {
    public static func toUInt32(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard let octet = UInt32(part), octet <= 255 else { return nil }
            value = (value << 8) | octet
        }
        return value
    }

    public static func toString(_ value: UInt32) -> String {
        "\((value >> 24) & 0xFF).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }

    /// Parses "192.168.1.0/24", "192.168.1.1-192.168.1.254", "192.168.1.1-254", or "192.168.1".
    public static func hosts(from input: String, limit: Int = 4096) -> [String]? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        if trimmed.contains("/") {
            let comps = trimmed.split(separator: "/")
            guard comps.count == 2, let base = toUInt32(String(comps[0])),
                  let prefix = Int(comps[1]), (0...32).contains(prefix) else { return nil }
            let mask: UInt32 = prefix == 0 ? 0 : ~UInt32(0) << (32 - prefix)
            let network = base & mask
            let broadcast = network | ~mask
            let first = prefix >= 31 ? network : network + 1
            let last = prefix >= 31 ? broadcast : broadcast - 1
            guard last >= first, Int(last - first) < limit else { return nil }
            return (first...last).map(toString)
        }

        if trimmed.contains("-") {
            let comps = trimmed.split(separator: "-")
            guard comps.count == 2, let start = toUInt32(String(comps[0])) else { return nil }
            let endStr = String(comps[1])
            let end: UInt32
            if let full = toUInt32(endStr) {
                end = full
            } else if let lastOctet = UInt32(endStr), lastOctet <= 255 {
                end = (start & 0xFFFFFF00) | lastOctet
            } else { return nil }
            guard end >= start, Int(end - start) < limit else { return nil }
            return (start...end).map(toString)
        }

        // Bare "a.b.c" → a.b.c.1 – a.b.c.254
        let dots = trimmed.filter { $0 == "." }.count
        if dots == 2 {
            guard let base = toUInt32(trimmed + ".0") else { return nil }
            return (1...254).map { toString(base | UInt32($0)) }
        }
        if let single = toUInt32(trimmed) { return [toString(single)] }
        return nil
    }
}

public struct DiscoveredHost: Sendable, Hashable, Codable, Identifiable {
    public var id: String { ip }
    public let ip: String
    public let rttMillis: Double
    public var hostname: String?
}

public enum ScanEvent: Sendable {
    case progress(scanned: Int, total: Int)
    case host(DiscoveredHost)
    case finished(aliveCount: Int)
    /// Terminal: nothing was scanned. A range the parser rejects used to arrive
    /// as "finished, 0 alive", which reads as a quiet network rather than as a
    /// typo in the range.
    case failed(String)
}

/// Sweeps an IPv4 range with concurrent single-probe pings to find live hosts.
public final class IPRangeScanner: Sendable {
    public init() {}

    public func scan(
        range: String,
        timeout: TimeInterval = 1.0,
        concurrency: Int = 48,
        resolveNames: Bool = true
    ) -> AsyncStream<ScanEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            guard let hosts = IPv4Range.hosts(from: range), !hosts.isEmpty else {
                continuation.yield(.failed("Некорректный диапазон: \(range)"))
                continuation.finish()
                return
            }

            let task = Task {
                let total = hosts.count
                var scanned = 0
                var alive = 0

                await withTaskGroup(of: DiscoveredHost?.self) { group in
                    var iterator = hosts.makeIterator()
                    var active = 0
                    func addNext() {
                        guard let ip = iterator.next() else { return }
                        active += 1
                        group.addTask {
                            guard let rtt = await Self.pingOnce(ip: ip, timeout: timeout) else { return nil }
                            var hostname: String? = nil
                            if resolveNames { hostname = try? await ReverseDNS.lookup(ip: ip) }
                            return DiscoveredHost(ip: ip, rttMillis: rtt, hostname: hostname)
                        }
                    }
                    for _ in 0..<max(1, concurrency) { addNext() }
                    while active > 0 {
                        guard let result = await group.next() else { break }
                        active -= 1
                        scanned += 1
                        continuation.yield(.progress(scanned: scanned, total: total))
                        if let host = result {
                            alive += 1
                            continuation.yield(.host(host))
                        }
                        if Task.isCancelled { break }
                        addNext()
                    }
                    group.cancelAll()
                }
                continuation.yield(.finished(aliveCount: alive))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func pingOnce(ip: String, timeout: TimeInterval) async -> Double? {
        // IPv4 on purpose: this sweeps an IPv4 subnet (each `ip` is a v4 literal).
        let config = PingConfig(count: 1, interval: 0.1, timeout: timeout, family: .ipv4)
        for await event in ICMPPinger().ping(host: ip, config: config) {
            if case .reply(let r) = event { return r.rttMillis }
        }
        return nil
    }
}
