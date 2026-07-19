import Foundation

/// Sends a Wake-on-LAN "magic packet" (6×0xFF followed by the target MAC ×16)
/// as a broadcast UDP datagram.
public enum WakeOnLan {
    public enum WoLError: Error, LocalizedError {
        case invalidMAC(String)
        case sendFailed(String)
        public var errorDescription: String? {
            switch self {
            case .invalidMAC(let m): return "Некорректный MAC-адрес: \(m)"
            case .sendFailed(let r): return "Не удалось отправить пакет: \(r)"
            }
        }
    }

    /// - Parameters:
    ///   - mac: MAC address like `AA:BB:CC:DD:EE:FF` (`:`, `-`, or `.` separated, or bare hex).
    ///   - broadcast: destination broadcast address (default 255.255.255.255).
    ///   - port: WoL port, usually 9 (or 7).
    public static func wake(mac: String, broadcast: String = "255.255.255.255", port: UInt16 = 9) throws {
        guard let macBytes = parseMAC(mac) else { throw WoLError.invalidMAC(mac) }
        let packet = magicPacket(mac: macBytes)

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw WoLError.sendFailed(String(cString: strerror(errno))) }
        defer { close(fd) }

        var enable: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr(broadcast)

        let sent = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                packet.withUnsafeBytes { raw in
                    sendto(fd, raw.baseAddress, raw.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent >= 0 else { throw WoLError.sendFailed(String(cString: strerror(errno))) }
    }

    public static func parseMAC(_ mac: String) -> [UInt8]? {
        let cleaned = mac.replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard cleaned.count == 12 else { return nil }
        var bytes = [UInt8]()
        var index = cleaned.startIndex
        for _ in 0..<6 {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    static func magicPacket(mac: [UInt8]) -> [UInt8] {
        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: mac) }
        return packet
    }
}
