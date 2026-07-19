import Foundation

/// A one-shot UDP request/response exchange with a timeout.
enum UDPExchange {
    static func request(
        endpoint: ResolvedEndpoint,
        payload: [UInt8],
        timeout: TimeInterval
    ) async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try requestBlocking(endpoint: endpoint, payload: payload, timeout: timeout)
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private static func requestBlocking(
        endpoint: ResolvedEndpoint,
        payload: [UInt8],
        timeout: TimeInterval
    ) throws -> [UInt8] {
        let domain = endpoint.family == .ipv4 ? AF_INET : AF_INET6
        let fd = socket(domain, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw NetworkError.socketCreationFailed(reason: String(cString: strerror(errno))) }
        defer { close(fd) }

        let connected = endpoint.withSockaddr { addr, len in connect(fd, addr, len) }
        guard connected == 0 else {
            throw NetworkError.sendFailed(reason: String(cString: strerror(errno)))
        }

        let sent = payload.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
        guard sent >= 0 else { throw NetworkError.sendFailed(reason: String(cString: strerror(errno))) }

        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let pr = poll(&pfd, 1, Int32(timeout * 1000))
        if pr == 0 { throw NetworkError.timedOut }
        guard pr > 0, (pfd.revents & Int16(POLLIN)) != 0 else {
            throw NetworkError.sendFailed(reason: "poll: \(String(cString: strerror(errno)))")
        }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let n = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
        guard n > 0 else { throw NetworkError.protocolError("пустой ответ") }
        return Array(buffer[0..<Int(n)])
    }
}
