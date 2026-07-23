import Foundation

/// A resolved socket address. Stores the raw sockaddr bytes so it stays `Sendable`
/// and can be handed to `connect`/`sendto` on any thread.
public struct ResolvedEndpoint: Sendable, Hashable {
    public let family: IPFamily
    public let ipString: String
    public let port: UInt16
    /// Raw `sockaddr` bytes (either `sockaddr_in` or `sockaddr_in6`).
    public let sockaddrBytes: [UInt8]

    public init(family: IPFamily, ipString: String, port: UInt16, sockaddrBytes: [UInt8]) {
        self.family = family
        self.ipString = ipString
        self.port = port
        self.sockaddrBytes = sockaddrBytes
    }

    /// Executes `body` with a pointer to the underlying sockaddr and its length.
    public func withSockaddr<R>(_ body: (UnsafePointer<sockaddr>, socklen_t) throws -> R) rethrows -> R {
        try sockaddrBytes.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: sockaddr.self).baseAddress!
            return try body(base, socklen_t(sockaddrBytes.count))
        }
    }

    public var addressFamilyValue: Int32 {
        family == .ipv4 ? AF_INET : AF_INET6
    }
}

public enum HostResolver {
    /// Resolves a hostname or literal IP into one or more endpoints.
    /// - Parameters:
    ///   - host: hostname or IP literal.
    ///   - port: TCP/UDP port (0 for raw ICMP).
    ///   - family: restrict to a family, or `nil` for both.
    public static func resolve(
        host: String,
        port: UInt16 = 0,
        family: IPFamily? = nil,
        timeout: TimeInterval = 8.0
    ) async throws -> [ResolvedEndpoint] {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NetworkError.invalidHost(host) }

        // Race the (uncancellable, potentially hanging) blocking resolve against a
        // hard timeout so a stuck DNS lookup can never silently freeze a test.
        return try await withThrowingTaskGroup(of: [ResolvedEndpoint].self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { cont in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            let results = try Self.resolveBlocking(host: trimmed, port: port, family: family)
                            cont.resume(returning: results)
                        } catch {
                            cont.resume(throwing: error)
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw NetworkError.resolutionFailed(host: trimmed, reason: "истекло время DNS (\(Int(timeout)) с)")
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw NetworkError.resolutionFailed(host: trimmed, reason: "нет результата")
            }
            return first
        }
    }

    /// Convenience: resolve and return the first endpoint (IPv4 preferred by default order).
    public static func resolveFirst(
        host: String,
        port: UInt16 = 0,
        family: IPFamily? = nil,
        timeout: TimeInterval = 8.0
    ) async throws -> ResolvedEndpoint {
        let all = try await resolve(host: host, port: port, family: family, timeout: timeout)
        guard let first = all.first else {
            throw NetworkError.resolutionFailed(host: host, reason: "нет адресов")
        }
        return first
    }

    private static func resolveBlocking(
        host: String,
        port: UInt16,
        family: IPFamily?
    ) throws -> [ResolvedEndpoint] {
        var hints = addrinfo()
        // Deliberately NOT AI_ADDRCONFIG. That flag drops a whole address family
        // unless a matching address is configured on a *local* interface — and
        // under a VPN (a `utun` tunnel) or NAT64/DNS64 the system often reports
        // no configured IPv4/IPv6, so getaddrinfo returns nothing and a hostname
        // "fails to resolve" even though the browser (which uses the system
        // resolver) resolves it fine. IP literals are unaffected, which is why
        // IP-address tests kept working while domain tests broke on VPN.
        hints.ai_flags = 0
        switch family {
        case .ipv4: hints.ai_family = AF_INET
        case .ipv6: hints.ai_family = AF_INET6
        case nil:   hints.ai_family = AF_UNSPEC
        }
        // We want addresses regardless of socktype; use STREAM so each address appears once.
        hints.ai_socktype = SOCK_STREAM

        var infoPtr: UnsafeMutablePointer<addrinfo>?
        let service = port == 0 ? nil : String(port)
        let status = getaddrinfo(host, service, &hints, &infoPtr)
        guard status == 0 else {
            let reason = String(cString: gai_strerror(status))
            throw NetworkError.resolutionFailed(host: host, reason: reason)
        }
        defer { if let infoPtr { freeaddrinfo(infoPtr) } }

        var endpoints: [ResolvedEndpoint] = []
        var seen = Set<String>()
        var cursor = infoPtr
        while let node = cursor {
            defer { cursor = node.pointee.ai_next }
            guard let addr = node.pointee.ai_addr else { continue }
            let len = Int(node.pointee.ai_addrlen)
            let fam: IPFamily
            switch node.pointee.ai_family {
            case AF_INET: fam = .ipv4
            case AF_INET6: fam = .ipv6
            default: continue
            }
            let bytes = [UInt8](UnsafeRawBufferPointer(start: addr, count: len))
            let ip = Self.ipString(from: addr, family: fam)
            let key = "\(fam.rawValue)|\(ip)"
            if seen.contains(key) { continue }
            seen.insert(key)
            endpoints.append(ResolvedEndpoint(family: fam, ipString: ip, port: port, sockaddrBytes: bytes))
        }

        guard !endpoints.isEmpty else {
            throw NetworkError.resolutionFailed(host: host, reason: "нет адресов")
        }
        // IPv4 first for broad compatibility, then IPv6.
        return endpoints.sorted { ($0.family == .ipv4 ? 0 : 1) < ($1.family == .ipv4 ? 0 : 1) }
    }

    static func ipString(from addr: UnsafePointer<sockaddr>, family: IPFamily) -> String {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        switch family {
        case .ipv4:
            addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                var a = sin.pointee.sin_addr
                inet_ntop(AF_INET, &a, &buffer, socklen_t(INET6_ADDRSTRLEN))
            }
        case .ipv6:
            addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
                var a = sin6.pointee.sin6_addr
                inet_ntop(AF_INET6, &a, &buffer, socklen_t(INET6_ADDRSTRLEN))
            }
        }
        return String(nullTerminated: buffer)
    }
}
