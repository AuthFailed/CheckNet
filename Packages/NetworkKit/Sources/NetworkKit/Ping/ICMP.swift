import Foundation

/// ICMP / ICMPv6 message-type constants and the internet checksum.
enum ICMP {
    static let echoRequestV4: UInt8 = 8
    static let echoReplyV4: UInt8 = 0
    static let timeExceededV4: UInt8 = 11
    static let destUnreachableV4: UInt8 = 3

    static let echoRequestV6: UInt8 = 128
    static let echoReplyV6: UInt8 = 129
    static let timeExceededV6: UInt8 = 3
    static let destUnreachableV6: UInt8 = 1

    /// Standard 16-bit one's-complement internet checksum (RFC 1071).
    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < bytes.count {
            let word = (UInt32(bytes[i]) << 8) | UInt32(bytes[i + 1])
            sum &+= word
            i += 2
        }
        if i < bytes.count {
            sum &+= UInt32(bytes[i]) << 8
        }
        while (sum >> 16) != 0 {
            sum = (sum & 0xFFFF) &+ (sum >> 16)
        }
        return UInt16(~sum & 0xFFFF)
    }

    /// Builds an ICMP echo request packet.
    /// - For IPv4 the checksum is computed here.
    /// - For IPv6 the kernel fills the checksum, so it is left zero.
    static func echoRequest(family: IPFamily, identifier: UInt16, sequence: UInt16, payload: [UInt8]) -> [UInt8] {
        let type = family == .ipv4 ? echoRequestV4 : echoRequestV6
        var packet = [UInt8]()
        packet.reserveCapacity(8 + payload.count)
        packet.append(type)          // type
        packet.append(0)             // code
        packet.append(0)             // checksum hi (placeholder)
        packet.append(0)             // checksum lo (placeholder)
        packet.append(UInt8(identifier >> 8))
        packet.append(UInt8(identifier & 0xFF))
        packet.append(UInt8(sequence >> 8))
        packet.append(UInt8(sequence & 0xFF))
        packet.append(contentsOf: payload)

        if family == .ipv4 {
            let ck = checksum(packet)
            packet[2] = UInt8(ck >> 8)
            packet[3] = UInt8(ck & 0xFF)
        }
        return packet
    }
}

/// A parsed ICMP reply extracted from a received datagram.
struct ParsedICMPReply {
    enum Kind: Equatable {
        case echoReply
        case timeExceeded
        case unreachable
        case other(type: UInt8)
    }
    let kind: Kind
    let identifier: UInt16
    let sequence: UInt16
}

extension ICMP {
    /// Parses a received datagram. `SOCK_DGRAM` ICMP sockets on Darwin usually strip
    /// the IPv4 header, but not always, so we detect and skip it when present.
    static func parseReply(_ data: [UInt8], family: IPFamily) -> ParsedICMPReply? {
        var offset = 0
        if family == .ipv4, let first = data.first, (first >> 4) == 4 {
            // Leading IPv4 header present; skip IHL*4 bytes.
            let ihl = Int(first & 0x0F) * 4
            if ihl >= 20 { offset = ihl }
        }
        guard data.count >= offset + 8 else { return nil }
        let type = data[offset]
        let echoReply = family == .ipv4 ? echoReplyV4 : echoReplyV6
        let timeExceeded = family == .ipv4 ? timeExceededV4 : timeExceededV6
        let unreachable = family == .ipv4 ? destUnreachableV4 : destUnreachableV6

        if type == echoReply {
            let ident = (UInt16(data[offset + 4]) << 8) | UInt16(data[offset + 5])
            let seq = (UInt16(data[offset + 6]) << 8) | UInt16(data[offset + 7])
            return ParsedICMPReply(kind: .echoReply, identifier: ident, sequence: seq)
        }

        // For error messages the original echo header is embedded after the ICMP
        // header (8 bytes) + the quoted IP header. Try to recover the sequence.
        if type == timeExceeded || type == unreachable {
            let (ident, seq) = extractQuotedEchoIdentity(data, errorHeaderOffset: offset, family: family)
            let kind: ParsedICMPReply.Kind = (type == timeExceeded) ? .timeExceeded : .unreachable
            return ParsedICMPReply(kind: kind, identifier: ident ?? 0, sequence: seq ?? 0)
        }

        return ParsedICMPReply(kind: .other(type: type), identifier: 0, sequence: 0)
    }

    /// Extracts identifier/sequence from the original echo packet quoted inside an ICMP error.
    private static func extractQuotedEchoIdentity(
        _ data: [UInt8],
        errorHeaderOffset: Int,
        family: IPFamily
    ) -> (UInt16?, UInt16?) {
        // Layout after the 8-byte ICMP error header: quoted IP header, then original ICMP echo.
        var p = errorHeaderOffset + 8
        if family == .ipv4 {
            guard data.count > p, (data[p] >> 4) == 4 else { return (nil, nil) }
            let ihl = Int(data[p] & 0x0F) * 4
            p += ihl
        } else {
            p += 40 // fixed IPv6 header
        }
        guard data.count >= p + 8 else { return (nil, nil) }
        let ident = (UInt16(data[p + 4]) << 8) | UInt16(data[p + 5])
        let seq = (UInt16(data[p + 6]) << 8) | UInt16(data[p + 7])
        return (ident, seq)
    }
}
