import XCTest
@testable import NetworkKit

/// Deterministic tests for the ICMP codec — checksum, packet building, reply
/// parsing. No sockets, no network.
final class ICMPTests: XCTestCase {

    // MARK: Checksum

    /// The worked example from RFC 1071 §3: these bytes checksum to 0x220D.
    func testChecksumRFC1071Vector() {
        let bytes: [UInt8] = [0x00, 0x01, 0xf2, 0x03, 0xf4, 0xf5, 0xf6, 0xf7]
        XCTAssertEqual(ICMP.checksum(bytes), 0x220D)
    }

    /// A packet that carries its own correct checksum re-checksums to zero.
    func testChecksumOfValidPacketIsZero() {
        let packet = ICMP.echoRequest(family: .ipv4, identifier: 0xABCD, sequence: 7,
                                      payload: Array("checknet".utf8))
        XCTAssertEqual(ICMP.checksum(packet), 0)
    }

    func testChecksumHandlesOddLength() {
        // Odd trailing byte is padded high; must not crash and stays 16-bit.
        let ck = ICMP.checksum([0x12, 0x34, 0x56])
        XCTAssertLessThanOrEqual(ck, 0xFFFF)
    }

    func testChecksumEmpty() {
        XCTAssertEqual(ICMP.checksum([]), 0xFFFF)   // ~0
    }

    // MARK: Packet building

    func testEchoRequestV4HeaderAndChecksum() {
        let packet = ICMP.echoRequest(family: .ipv4, identifier: 0x1234, sequence: 0x0009, payload: [0xAA, 0xBB])
        XCTAssertEqual(packet[0], 8)      // echo request v4
        XCTAssertEqual(packet[1], 0)      // code
        XCTAssertEqual(packet[4], 0x12)   // identifier hi
        XCTAssertEqual(packet[5], 0x34)   // identifier lo
        XCTAssertEqual(packet[6], 0x00)   // sequence hi
        XCTAssertEqual(packet[7], 0x09)   // sequence lo
        XCTAssertEqual(Array(packet.suffix(2)), [0xAA, 0xBB])
        XCTAssertFalse(packet[2] == 0 && packet[3] == 0, "v4 checksum must be filled")
    }

    func testEchoRequestV6LeavesChecksumForKernel() {
        let packet = ICMP.echoRequest(family: .ipv6, identifier: 0x1234, sequence: 1, payload: [])
        XCTAssertEqual(packet[0], 128)    // echo request v6
        XCTAssertEqual(packet[2], 0)      // checksum left zero
        XCTAssertEqual(packet[3], 0)
    }

    // MARK: Reply parsing

    func testParseEchoReplyV4NoIPHeader() {
        // SOCK_DGRAM usually strips the IP header.
        let reply: [UInt8] = [0, 0, 0, 0, 0x12, 0x34, 0x00, 0x2A]
        let parsed = ICMP.parseReply(reply, family: .ipv4)
        XCTAssertEqual(parsed?.kind, .echoReply)
        XCTAssertEqual(parsed?.identifier, 0x1234)
        XCTAssertEqual(parsed?.sequence, 0x2A)
    }

    func testParseEchoReplyV4SkipsLeadingIPHeader() {
        // 20-byte IPv4 header (IHL=5) followed by the ICMP echo reply.
        var packet: [UInt8] = [0x45]                       // version 4, IHL 5
        packet += [UInt8](repeating: 0, count: 19)         // rest of the IP header
        packet += [0, 0, 0, 0, 0xDE, 0xAD, 0x00, 0x05]     // ICMP echo reply
        let parsed = ICMP.parseReply(packet, family: .ipv4)
        XCTAssertEqual(parsed?.kind, .echoReply)
        XCTAssertEqual(parsed?.identifier, 0xDEAD)
        XCTAssertEqual(parsed?.sequence, 5)
    }

    func testParseTimeExceededRecoversQuotedSequence() {
        // ICMP error (8 bytes) + quoted IPv4 header (20) + original echo (8).
        var packet: [UInt8] = [11, 0, 0, 0, 0, 0, 0, 0]    // time exceeded header
        var quotedIP: [UInt8] = [0x45]
        quotedIP += [UInt8](repeating: 0, count: 19)
        packet += quotedIP
        packet += [8, 0, 0, 0, 0xBE, 0xEF, 0x00, 0x11]     // original echo request
        let parsed = ICMP.parseReply(packet, family: .ipv4)
        XCTAssertEqual(parsed?.kind, .timeExceeded)
        XCTAssertEqual(parsed?.identifier, 0xBEEF)
        XCTAssertEqual(parsed?.sequence, 0x11)
    }

    func testParseUnreachableV4() {
        var packet: [UInt8] = [3, 0, 0, 0, 0, 0, 0, 0]     // dest unreachable
        packet += [0x45] + [UInt8](repeating: 0, count: 19)
        packet += [8, 0, 0, 0, 0x00, 0x01, 0x00, 0x02]
        XCTAssertEqual(ICMP.parseReply(packet, family: .ipv4)?.kind, .unreachable)
    }

    func testParseEchoReplyV6() {
        let reply: [UInt8] = [129, 0, 0, 0, 0xAB, 0xCD, 0x00, 0x03]
        let parsed = ICMP.parseReply(reply, family: .ipv6)
        XCTAssertEqual(parsed?.kind, .echoReply)
        XCTAssertEqual(parsed?.identifier, 0xABCD)
        XCTAssertEqual(parsed?.sequence, 3)
    }

    func testParseTruncatedReturnsNil() {
        XCTAssertNil(ICMP.parseReply([0, 0, 0], family: .ipv4))   // < 8 bytes
    }

    func testParseUnknownTypeIsOther() {
        let reply: [UInt8] = [42, 0, 0, 0, 0, 0, 0, 0]
        XCTAssertEqual(ICMP.parseReply(reply, family: .ipv4)?.kind, .other(type: 42))
    }
}
