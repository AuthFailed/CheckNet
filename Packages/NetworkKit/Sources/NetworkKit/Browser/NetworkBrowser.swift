import Foundation

public struct DiscoveredDevice: Sendable, Hashable, Codable, Identifiable {
    public var id: String { ip }
    public let ip: String
    public var mac: String?
    public var vendor: String?
    public var hostname: String?
    public var rttMillis: Double?
    public var isGateway: Bool
    public var isSelf: Bool
    public var randomizedMAC: Bool

    public var displayName: String {
        hostname ?? vendor ?? (isGateway ? "Шлюз" : ip)
    }
}

public enum BrowserEvent: Sendable {
    case device(DiscoveredDevice)
    case progress(scanned: Int, total: Int)
    case finished(count: Int)
    /// Terminal: the sweep never ran. Carries the scanner's own reason when the
    /// range it was given turned out to be unusable.
    case failed(String)
}

/// Discovers devices on the local network: ping sweep → ARP (MAC) → OUI vendor
/// → reverse DNS, merged into a device list. Fully self-contained.
public final class NetworkBrowser: Sendable {
    public init() {}

    public func browse(cidr: String? = nil, timeout: TimeInterval = 1.0) -> AsyncStream<BrowserEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                let range = cidr ?? NetworkInterfaces.primaryIPv4CIDR() ?? "192.168.1.0/24"
                let localIP = NetworkInterfaces.list(includeIPv6: false)
                    .first { $0.name.hasPrefix("en") || $0.name.hasPrefix("pdp") }?.address
                let gateway = Self.gatewayGuess(from: localIP)

                var count = 0
                for await event in IPRangeScanner().scan(range: range, timeout: timeout, resolveNames: true) {
                    if Task.isCancelled { break }
                    switch event {
                    case .progress(let s, let t):
                        continuation.yield(.progress(scanned: s, total: t))
                    case .host(let host):
                        let arp = ARPTable.entries()
                        let mac = arp[host.ip]
                        let vendor = mac.flatMap { MACVendor.lookup(mac: $0) }
                        count += 1
                        continuation.yield(.device(DiscoveredDevice(
                            ip: host.ip,
                            mac: mac,
                            vendor: vendor,
                            hostname: host.hostname,
                            rttMillis: host.rttMillis,
                            isGateway: host.ip == gateway,
                            isSelf: host.ip == localIP,
                            randomizedMAC: mac.map { MACVendor.isRandomized(mac: $0) } ?? false
                        )))
                    case .finished:
                        break
                    case .failed(let reason):
                        continuation.yield(.failed(reason))
                        continuation.finish()
                        return
                    }
                }
                continuation.yield(.finished(count: count))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func gatewayGuess(from localIP: String?) -> String? {
        guard let localIP else { return nil }
        let parts = localIP.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return "\(parts[0]).\(parts[1]).\(parts[2]).1"
    }
}
