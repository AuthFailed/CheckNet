import Foundation

/// Measures a through-proxy reachability check: connect to a local SOCKS5
/// inbound (an Xray core), CONNECT to a neutral target, send an HTTP GET and
/// time the whole round-trip. This is what turns a running core into a real
/// "does the proxy work / how far" ping.
public enum Socks5Probe {
    public struct Result: Sendable, Equatable {
        public let latencyMillis: Double
        public let httpStatus: Int?
    }

    public enum ProbeError: Error, Equatable, Sendable {
        case connectFailed, handshakeFailed, connectRefusedByProxy(UInt8), noResponse
    }

    /// Probe `host:port` (default `www.gstatic.com:80`, path `/generate_204`)
    /// through the SOCKS proxy on `127.0.0.1:socksPort`.
    public static func probe(
        socksPort: Int,
        host: String = "www.gstatic.com",
        port: UInt16 = 80,
        path: String = "/generate_204",
        timeout: TimeInterval = 12
    ) async throws -> Result {
        let endpoint = try await HostResolver.resolveFirst(host: "127.0.0.1", port: UInt16(socksPort), family: .ipv4)
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do { cont.resume(returning: try run(endpoint, host: host, port: port, path: path, timeout: timeout)) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    private static func run(_ endpoint: ResolvedEndpoint, host: String, port: UInt16,
                            path: String, timeout: TimeInterval) throws -> Result {
        let start = MonoClock.nanos()
        let fd: Int32
        do { fd = try TCPTransport.connect(endpoint: endpoint, timeout: timeout).fd }
        catch { throw ProbeError.connectFailed }
        defer { close(fd) }

        // Greeting: version 5, one method, no-auth.
        try? TCPTransport.writeAll(fd: fd, bytes: [0x05, 0x01, 0x00])
        let greeting = (try? TCPTransport.readExactly(fd: fd, count: 2, timeout: timeout)) ?? []
        guard greeting.count == 2, greeting[0] == 0x05, greeting[1] == 0x00 else { throw ProbeError.handshakeFailed }

        // CONNECT to host:port (domain address type).
        var req: [UInt8] = [0x05, 0x01, 0x00, 0x03, UInt8(host.utf8.count)]
        req += Array(host.utf8)
        req += [UInt8(port >> 8), UInt8(port & 0xFF)]
        try? TCPTransport.writeAll(fd: fd, bytes: req)

        // Reply: VER REP RSV ATYP + bound address. Read header, then skip addr.
        let head = (try? TCPTransport.readExactly(fd: fd, count: 4, timeout: timeout)) ?? []
        guard head.count == 4, head[0] == 0x05 else { throw ProbeError.handshakeFailed }
        guard head[1] == 0x00 else { throw ProbeError.connectRefusedByProxy(head[1]) }
        let atyp = head[3]
        let addrLen: Int
        switch atyp {
        case 0x01: addrLen = 4 + 2                              // IPv4 + port
        case 0x04: addrLen = 16 + 2                             // IPv6 + port
        case 0x03:
            let l = (try? TCPTransport.readExactly(fd: fd, count: 1, timeout: timeout)) ?? [0]
            addrLen = Int(l.first ?? 0) + 2
        default: throw ProbeError.handshakeFailed
        }
        _ = try? TCPTransport.readExactly(fd: fd, count: addrLen, timeout: timeout)

        // Tunnelled HTTP GET → first response bytes.
        let getReq = "GET \(path) HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\nUser-Agent: CheckNet\r\n\r\n"
        try? TCPTransport.writeAll(fd: fd, bytes: Array(getReq.utf8))
        let response = (try? TCPTransport.readUntilClose(fd: fd, timeout: timeout, maxBytes: 4096)) ?? []
        guard !response.isEmpty else { throw ProbeError.noResponse }

        let latency = MonoClock.millisSince(start)
        return Result(latencyMillis: latency, httpStatus: httpStatus(response))
    }

    /// Parse the status code from an "HTTP/1.1 204 ..." response line.
    static func httpStatus(_ bytes: [UInt8]) -> Int? {
        guard let line = String(bytes: bytes.prefix(64), encoding: .utf8) ?? String(bytes: bytes.prefix(64), encoding: .isoLatin1),
              line.hasPrefix("HTTP/") else { return nil }
        let parts = line.split(separator: " ")
        return parts.count >= 2 ? Int(parts[1]) : nil
    }
}
