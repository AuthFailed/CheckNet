import Foundation

/// Reverse DNS (PTR) lookups via `getnameinfo`.
public enum ReverseDNS {
    public static func lookup(ip: String) async throws -> String? {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(returning: lookupBlocking(ip: ip))
            }
        }
    }

    private static func lookupBlocking(ip: String) -> String? {
        var hints = addrinfo()
        hints.ai_flags = AI_NUMERICHOST
        hints.ai_family = AF_UNSPEC
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(ip, nil, &hints, &info) == 0, let node = info else { return nil }
        defer { freeaddrinfo(info) }

        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let rc = getnameinfo(node.pointee.ai_addr, node.pointee.ai_addrlen,
                             &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
        guard rc == 0 else { return nil }
        let name = String(cString: host)
        return name == ip ? nil : name
    }
}

/// Forward host → IP resolution results.
public struct HostLookupResult: Sendable, Hashable, Codable {
    public let host: String
    public let addresses: [ResolvedAddress]
    public struct ResolvedAddress: Sendable, Hashable, Codable, Identifiable {
        public var id: String { ip }
        public let ip: String
        public let family: IPFamily
    }
}

public enum HostLookup {
    public static func resolve(host: String, family: IPFamily? = nil) async throws -> HostLookupResult {
        let endpoints = try await HostResolver.resolve(host: host, family: family)
        let addrs = endpoints.map { HostLookupResult.ResolvedAddress(ip: $0.ipString, family: $0.family) }
        return HostLookupResult(host: host, addresses: addrs)
    }
}

/// A local network interface.
public struct NetworkInterface: Sendable, Hashable, Codable, Identifiable {
    public var id: String { name + "|" + address }
    public let name: String
    public let address: String
    public let netmask: String?
    public let family: IPFamily
    public let isUp: Bool
    public let isLoopback: Bool
    public let broadcast: String?

    /// Friendly label for common BSD interface names.
    public var friendlyName: String {
        switch true {
        case name == "en0": return "Wi-Fi / Ethernet (en0)"
        case name.hasPrefix("en"): return "Ethernet (\(name))"
        case name.hasPrefix("pdp_ip"): return "Сотовая (\(name))"
        case name.hasPrefix("utun"), name.hasPrefix("ipsec"), name.hasPrefix("tun"): return "VPN (\(name))"
        case name == "lo0": return "Loopback (lo0)"
        case name.hasPrefix("awdl"): return "AWDL (\(name))"
        case name.hasPrefix("bridge"): return "Bridge (\(name))"
        default: return name
        }
    }
}

public enum NetworkInterfaces {
    /// Enumerates active interfaces with IPv4/IPv6 addresses.
    public static func list(includeLoopback: Bool = false, includeIPv6: Bool = true) -> [NetworkInterface] {
        var result: [NetworkInterface] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return [] }
        defer { freeifaddrs(ifaddrPtr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let node = cursor {
            defer { cursor = node.pointee.ifa_next }
            guard let addr = node.pointee.ifa_addr else { continue }
            let family = addr.pointee.sa_family
            let fam: IPFamily
            if family == UInt8(AF_INET) { fam = .ipv4 }
            else if family == UInt8(AF_INET6) { fam = .ipv6 }
            else { continue }
            if fam == .ipv6 && !includeIPv6 { continue }

            let flags = Int32(node.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            if isLoopback && !includeLoopback { continue }

            let name = String(cString: node.pointee.ifa_name)
            let ip = ipString(addr, family: fam)
            let mask = node.pointee.ifa_netmask.map { ipString($0, family: fam) }
            let bcast = (flags & IFF_BROADCAST) != 0
                ? node.pointee.ifa_dstaddr.map { ipString($0, family: fam) }
                : nil

            result.append(NetworkInterface(
                name: name, address: ip, netmask: mask, family: fam,
                isUp: isUp, isLoopback: isLoopback, broadcast: bcast
            ))
        }
        // Real interfaces first (en, then others), IPv4 before IPv6.
        return result.sorted {
            if $0.family != $1.family { return $0.family == .ipv4 }
            return $0.name < $1.name
        }
    }

    private static func ipString(_ addr: UnsafeMutablePointer<sockaddr>, family: IPFamily) -> String {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let len = family == .ipv4 ? socklen_t(MemoryLayout<sockaddr_in>.size) : socklen_t(MemoryLayout<sockaddr_in6>.size)
        getnameinfo(addr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
        var s = String(cString: host)
        // Strip IPv6 scope id suffix (e.g. fe80::1%en0).
        if let pct = s.firstIndex(of: "%") { s = String(s[..<pct]) }
        return s
    }
}
