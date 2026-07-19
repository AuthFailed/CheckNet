import Foundation

/// Reusable blocking-with-timeout TCP primitives (connect / read / write).
/// Used by DNS-over-TCP fallback, TCP port checks, and the TLS inspector.
enum TCPTransport {
    /// Connects to `endpoint`, returning the connected socket and the connect latency (ms).
    /// The returned socket is in blocking mode.
    static func connect(endpoint: ResolvedEndpoint, timeout: TimeInterval) throws -> (fd: Int32, latencyMillis: Double) {
        let domain = endpoint.family == .ipv4 ? AF_INET : AF_INET6
        let fd = socket(domain, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { throw NetworkError.socketCreationFailed(reason: String(cString: strerror(errno))) }

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let start = MonoClock.nanos()
        let rc = endpoint.withSockaddr { addr, len in Darwin.connect(fd, addr, len) }
        if rc != 0 {
            if errno != EINPROGRESS {
                let reason = String(cString: strerror(errno))
                close(fd)
                throw NetworkError.sendFailed(reason: reason)
            }
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let pr = poll(&pfd, 1, Int32(timeout * 1000))
            if pr == 0 { close(fd); throw NetworkError.timedOut }
            guard pr > 0 else { close(fd); throw NetworkError.sendFailed(reason: String(cString: strerror(errno))) }
            // Confirm the connection actually succeeded.
            var sockErr: Int32 = 0
            var l = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &sockErr, &l)
            if sockErr != 0 {
                close(fd)
                throw NetworkError.sendFailed(reason: String(cString: strerror(sockErr)))
            }
        }
        let latency = MonoClock.millisSince(start)
        // Back to blocking for straightforward request/response use.
        _ = fcntl(fd, F_SETFL, flags)
        return (fd, latency)
    }

    static func writeAll(fd: Int32, bytes: [UInt8]) throws {
        var offset = 0
        try bytes.withUnsafeBytes { raw in
            while offset < bytes.count {
                let n = send(fd, raw.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                if n <= 0 {
                    if errno == EINTR { continue }
                    throw NetworkError.sendFailed(reason: String(cString: strerror(errno)))
                }
                offset += n
            }
        }
    }

    /// Reads exactly `count` bytes (with a total deadline), or throws.
    static func readExactly(fd: Int32, count: Int, timeout: TimeInterval) throws -> [UInt8] {
        var buffer = [UInt8]()
        buffer.reserveCapacity(count)
        let deadline = MonoClock.nanos() + UInt64(timeout * 1_000_000_000)
        var chunk = [UInt8](repeating: 0, count: count)
        while buffer.count < count {
            let remainingNanos = deadline > MonoClock.nanos() ? deadline - MonoClock.nanos() : 0
            if remainingNanos == 0 { throw NetworkError.timedOut }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let pr = poll(&pfd, 1, Int32(remainingNanos / 1_000_000))
            if pr == 0 { throw NetworkError.timedOut }
            guard pr > 0 else { throw NetworkError.protocolError("poll: \(String(cString: strerror(errno)))") }
            let want = count - buffer.count
            let n = chunk.withUnsafeMutableBytes { recv(fd, $0.baseAddress, want, 0) }
            if n == 0 { break } // peer closed
            if n < 0 {
                if errno == EINTR { continue }
                throw NetworkError.protocolError(String(cString: strerror(errno)))
            }
            buffer.append(contentsOf: chunk[0..<n])
        }
        return buffer
    }

    /// A DNS-over-TCP exchange (2-byte length prefix), used for truncated responses.
    static func dnsRequest(endpoint: ResolvedEndpoint, query: [UInt8], timeout: TimeInterval) throws -> [UInt8] {
        let (fd, _) = try connect(endpoint: endpoint, timeout: timeout)
        defer { close(fd) }
        var framed = [UInt8]()
        framed.append(UInt8(query.count >> 8))
        framed.append(UInt8(query.count & 0xFF))
        framed.append(contentsOf: query)
        try writeAll(fd: fd, bytes: framed)

        let lenBytes = try readExactly(fd: fd, count: 2, timeout: timeout)
        let respLen = (Int(lenBytes[0]) << 8) | Int(lenBytes[1])
        guard respLen > 0 else { throw NetworkError.protocolError("нулевая длина TCP DNS") }
        return try readExactly(fd: fd, count: respLen, timeout: timeout)
    }
}
