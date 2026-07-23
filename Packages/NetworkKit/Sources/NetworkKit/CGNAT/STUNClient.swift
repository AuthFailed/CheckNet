import Foundation

/// Minimal STUN client (RFC 5389) to discover the public IP via a Binding Request.
public struct STUNClient: Sendable {
    public init() {}

    public struct PublicAddress: Sendable, Hashable { public let ip: String; public let port: UInt16 }

    public static let defaultServers = [
        ("stun.l.google.com", UInt16(19302)),
        ("stun1.l.google.com", UInt16(19302)),
        ("stun.cloudflare.com", UInt16(3478))
    ]

    public func discover(timeout: TimeInterval = 3.0) async throws -> PublicAddress {
        for (host, port) in Self.defaultServers {
            if let addr = try? await query(server: host, port: port, timeout: timeout) {
                return addr
            }
        }
        throw NetworkError.timedOut
    }

    func query(server: String, port: UInt16, timeout: TimeInterval) async throws -> PublicAddress {
        // IPv4 on purpose: this detects IPv4 (CG)NAT. IPv6 is typically not NATed,
        // so a v6 STUN result wouldn't answer the question the tool asks.
        let endpoint = try await HostResolver.resolveFirst(host: server, port: port, family: .ipv4)
        let request = Self.bindingRequest()
        let response = try await UDPExchange.request(endpoint: endpoint, payload: request, timeout: timeout)
        guard let addr = Self.parseResponse(response) else {
            throw NetworkError.protocolError("некорректный STUN-ответ")
        }
        return addr
    }

    private static let magicCookie: [UInt8] = [0x21, 0x12, 0xA4, 0x42]

    static func bindingRequest() -> [UInt8] {
        var msg = [UInt8]()
        msg.append(0x00); msg.append(0x01)   // Binding Request
        msg.append(0x00); msg.append(0x00)   // length 0
        msg.append(contentsOf: magicCookie)
        // 12-byte transaction id (fixed pattern; response echoes it).
        for i in 0..<12 { msg.append(UInt8((i * 37 + 11) & 0xFF)) }
        return msg
    }

    static func parseResponse(_ data: [UInt8]) -> PublicAddress? {
        guard data.count >= 20, data[0] == 0x01, data[1] == 0x01 else { return nil }
        var p = 20
        while p + 4 <= data.count {
            let type = (UInt16(data[p]) << 8) | UInt16(data[p + 1])
            let len = Int((UInt16(data[p + 2]) << 8) | UInt16(data[p + 3]))
            let valueStart = p + 4
            guard valueStart + len <= data.count else { break }

            if type == 0x0020 || type == 0x0001 { // XOR-MAPPED-ADDRESS or MAPPED-ADDRESS
                if let addr = parseAddress(data, start: valueStart, length: len, xor: type == 0x0020) {
                    return addr
                }
            }
            p = valueStart + len + ((4 - (len % 4)) % 4) // 4-byte alignment
        }
        return nil
    }

    private static func parseAddress(_ data: [UInt8], start: Int, length: Int, xor: Bool) -> PublicAddress? {
        guard length >= 8, data[start + 1] == 0x01 else { return nil } // IPv4 only
        var port = (UInt16(data[start + 2]) << 8) | UInt16(data[start + 3])
        var octets = [data[start + 4], data[start + 5], data[start + 6], data[start + 7]]
        if xor {
            port ^= 0x2112
            for i in 0..<4 { octets[i] ^= magicCookie[i] }
        }
        let ip = "\(octets[0]).\(octets[1]).\(octets[2]).\(octets[3])"
        return PublicAddress(ip: ip, port: port)
    }
}
