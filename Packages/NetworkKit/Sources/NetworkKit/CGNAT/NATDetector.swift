import Foundation

public struct NATReport: Sendable {
    public enum NATType: String, Sendable {
        case none = "Direct connection"
        case singleNAT = "Single NAT"
        case doubleNAT = "Double NAT"
        case cgnat = "CGNAT (carrier)"
        case unknown = "Not determined"
    }

    public let localIP: String?
    public let publicIP: String?
    public let natType: NATType
    public let privateHops: [String]     // private/CGNAT router IPs on the path
    public let cgnatHops: [String]       // 100.64.0.0/10 hops
    public let findings: [String]
}

/// Detects NAT topology by comparing the local address, the STUN-discovered
/// public address, and the private/CGNAT routers seen on the outbound path.
public struct NATDetector: Sendable {
    public init() {}

    public func detect() async -> NATReport {
        let localIP = NetworkInterfaces.list(includeIPv6: false)
            .first { $0.name.hasPrefix("en") || $0.name.hasPrefix("pdp") }?.address

        let publicIP = try? await STUNClient().discover().ip

        // Trace the first several hops toward a public anchor to inspect NAT layers.
        var privateHops: [String] = []
        var cgnatHops: [String] = []
        for await event in Traceroute().trace(host: "1.1.1.1",
                                              config: .init(maxHops: 8, probesPerHop: 1, timeout: 1.0, resolveNames: false)) {
            if case .hop(let hop) = event, let ip = hop.routerIP {
                if Self.isCGNAT(ip) { cgnatHops.append(ip); privateHops.append(ip) }
                else if Self.isPrivate(ip) { privateHops.append(ip) }
            }
        }

        var findings: [String] = []
        var type: NATReport.NATType = .unknown

        if let localIP, let publicIP {
            if localIP == publicIP {
                type = .none
                findings.append("Local and external addresses match — you're directly on the internet.")
            } else if !cgnatHops.isEmpty {
                type = .cgnat
                findings.append("A CGNAT address (100.64.0.0/10) was found on the path: \(cgnatHops.joined(separator: ", ")).")
                findings.append("The carrier uses Carrier-Grade NAT — incoming connections and port forwarding are unavailable.")
            } else if privateHops.count >= 2 {
                type = .doubleNAT
                findings.append("Two or more private routers on the path — Double NAT is likely.")
            } else if Self.isPrivate(localIP) {
                type = .singleNAT
                findings.append("Standard home NAT: a private local address behind a single router.")
            } else {
                type = .none
            }
            findings.append("Local: \(localIP) · external: \(publicIP).")
        } else if publicIP == nil {
            findings.append("Couldn't determine the external address (STUN unavailable).")
        }

        return NATReport(localIP: localIP, publicIP: publicIP, natType: type,
                         privateHops: privateHops, cgnatHops: cgnatHops, findings: findings)
    }

    static func isCGNAT(_ ip: String) -> Bool {
        // 100.64.0.0/10 → 100.64.0.0 – 100.127.255.255
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 100 && (64...127).contains(parts[1])
    }

    static func isPrivate(_ ip: String) -> Bool {
        if ip.hasPrefix("10.") || ip.hasPrefix("192.168.") { return true }
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4, parts[0] == 172, (16...31).contains(parts[1]) { return true }
        return false
    }
}
