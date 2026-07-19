import Foundation

// Darwin socket options missing from the Swift overlay (from <netinet6/in6.h>).
private let kIPV6_RECVHOPLIMIT: Int32 = 37
private let kIPV6_HOPLIMIT: Int32 = 47

/// Low-level socket helpers shared by ICMP ping and traceroute.
enum SocketFactory {
    struct ReceivedDatagram {
        let data: [UInt8]
        let ttl: Int?
        let sourceIP: String?
    }

    enum MakeResult {
        case success(Int32)
        case failure(String)
    }

    /// Creates a non-blocking unprivileged ICMP datagram socket configured per `config`.
    static func makeICMP(endpoint: ResolvedEndpoint, config: PingConfig) -> MakeResult {
        let domain = endpoint.family == .ipv4 ? AF_INET : AF_INET6
        let proto = endpoint.family == .ipv4 ? IPPROTO_ICMP : IPPROTO_ICMPV6
        let fd = socket(domain, SOCK_DGRAM, proto)
        guard fd >= 0 else { return .failure(String(cString: strerror(errno))) }

        // Non-blocking.
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        configureCommon(fd: fd, family: endpoint.family, ttl: config.ttl, dontFragment: config.dontFragment)
        return .success(fd)
    }

    /// Applies TTL/hop-limit, DF, and TTL-receiving options.
    static func configureCommon(fd: Int32, family: IPFamily, ttl: Int?, dontFragment: Bool) {
        if family == .ipv4 {
            if let ttl {
                var v = Int32(ttl)
                setsockopt(fd, IPPROTO_IP, IP_TTL, &v, socklen_t(MemoryLayout<Int32>.size))
            }
            var recvTTL: Int32 = 1
            setsockopt(fd, IPPROTO_IP, IP_RECVTTL, &recvTTL, socklen_t(MemoryLayout<Int32>.size))
            if dontFragment {
                var one: Int32 = 1
                setsockopt(fd, IPPROTO_IP, IP_DONTFRAG, &one, socklen_t(MemoryLayout<Int32>.size))
            }
        } else {
            if let ttl {
                var v = Int32(ttl)
                setsockopt(fd, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &v, socklen_t(MemoryLayout<Int32>.size))
            }
            var recvHops: Int32 = 1
            setsockopt(fd, IPPROTO_IPV6, kIPV6_RECVHOPLIMIT, &recvHops, socklen_t(MemoryLayout<Int32>.size))
        }
    }

    /// Reads one datagram (non-blocking). Returns nil when the socket would block or errors.
    static func receive(fd: Int32, family: IPFamily) -> ReceivedDatagram? {
        var dataBuf = [UInt8](repeating: 0, count: 2048)
        var controlBuf = [UInt8](repeating: 0, count: 512)
        var srcStorage = sockaddr_storage()

        return withUnsafeMutablePointer(to: &srcStorage) { srcPtr -> ReceivedDatagram? in
            srcPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { srcSock in
                dataBuf.withUnsafeMutableBytes { dataRaw in
                    controlBuf.withUnsafeMutableBytes { ctrlRaw in
                        var iov = iovec(iov_base: dataRaw.baseAddress, iov_len: dataRaw.count)
                        return withUnsafeMutablePointer(to: &iov) { iovPtr -> ReceivedDatagram? in
                            var msg = msghdr()
                            msg.msg_name = UnsafeMutableRawPointer(srcSock)
                            msg.msg_namelen = socklen_t(MemoryLayout<sockaddr_storage>.size)
                            msg.msg_iov = iovPtr
                            msg.msg_iovlen = 1
                            msg.msg_control = ctrlRaw.baseAddress
                            msg.msg_controllen = socklen_t(ctrlRaw.count)

                            let n = recvmsg(fd, &msg, 0)
                            guard n > 0 else { return nil }

                            let bytes = Array(UnsafeRawBufferPointer(start: dataRaw.baseAddress, count: Int(n)))
                            let ttl = extractTTL(msg: &msg, family: family)
                            let ip = sourceIP(from: srcSock, family: family)
                            return ReceivedDatagram(data: bytes, ttl: ttl, sourceIP: ip)
                        }
                    }
                }
            }
        }
    }

    /// Parses the control message buffer for the received TTL / hop limit.
    private static func extractTTL(msg: inout msghdr, family: IPFamily) -> Int? {
        let wantLevel = family == .ipv4 ? IPPROTO_IP : IPPROTO_IPV6
        let wantType = family == .ipv4 ? IP_RECVTTL : kIPV6_HOPLIMIT

        guard var cmsg = firstCmsg(&msg) else { return nil }
        while true {
            if Int(cmsg.pointee.cmsg_level) == wantLevel && Int(cmsg.pointee.cmsg_type) == wantType {
                let dataPtr = cmsgData(cmsg)
                // IPv4 IP_RECVTTL delivers a single byte; IPv6 hop limit an int.
                if family == .ipv4 {
                    return Int(dataPtr.load(as: UInt8.self))
                } else {
                    return Int(dataPtr.load(as: Int32.self))
                }
            }
            guard let next = nextCmsg(&msg, cmsg) else { break }
            cmsg = next
        }
        return nil
    }

    private static func sourceIP(from addr: UnsafePointer<sockaddr>, family: IPFamily) -> String? {
        HostResolver.ipString(from: addr, family: family)
    }

    // MARK: - CMSG macros (Darwin, 4-byte alignment)

    private static func align(_ length: Int) -> Int { (length + 3) & ~3 }
    private static var cmsgHeaderLen: Int { align(MemoryLayout<cmsghdr>.size) }

    private static func firstCmsg(_ msg: inout msghdr) -> UnsafeMutablePointer<cmsghdr>? {
        guard Int(msg.msg_controllen) >= MemoryLayout<cmsghdr>.size,
              let control = msg.msg_control else { return nil }
        return control.assumingMemoryBound(to: cmsghdr.self)
    }

    private static func cmsgData(_ cmsg: UnsafeMutablePointer<cmsghdr>) -> UnsafeRawPointer {
        UnsafeRawPointer(cmsg).advanced(by: cmsgHeaderLen)
    }

    private static func nextCmsg(_ msg: inout msghdr, _ cmsg: UnsafeMutablePointer<cmsghdr>) -> UnsafeMutablePointer<cmsghdr>? {
        let cmsgLen = Int(cmsg.pointee.cmsg_len)
        guard cmsgLen >= MemoryLayout<cmsghdr>.size else { return nil }
        let next = UnsafeMutableRawPointer(cmsg).advanced(by: align(cmsgLen))
        guard let controlStart = msg.msg_control else { return nil }
        let end = controlStart.advanced(by: Int(msg.msg_controllen))
        // Ensure the next header (fixed part) fits within the control buffer.
        if next.advanced(by: MemoryLayout<cmsghdr>.size) > end { return nil }
        return next.assumingMemoryBound(to: cmsghdr.self)
    }
}
