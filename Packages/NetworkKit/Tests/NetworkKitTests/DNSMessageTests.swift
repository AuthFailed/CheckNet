import XCTest
@testable import NetworkKit

/// Deterministic codec tests for `DNSMessage` — no network. Responses are built
/// byte-for-byte so every RFC 1035 edge case (compression, hostile pointers,
/// truncation, oversized names) is exercised directly against the parser.
final class DNSMessageTests: XCTestCase {

    // MARK: Builders

    /// A 12-byte DNS header. Flags default to a plain response (QR=1, RD, RA).
    private func header(id: UInt16 = 0x1234, flags: UInt16 = 0x8180,
                        qd: UInt16 = 0, an: UInt16 = 0, ns: UInt16 = 0, ar: UInt16 = 0) -> [UInt8] {
        [UInt8(id >> 8), UInt8(id & 0xFF),
         UInt8(flags >> 8), UInt8(flags & 0xFF),
         UInt8(qd >> 8), UInt8(qd & 0xFF),
         UInt8(an >> 8), UInt8(an & 0xFF),
         UInt8(ns >> 8), UInt8(ns & 0xFF),
         UInt8(ar >> 8), UInt8(ar & 0xFF)]
    }

    private func u16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }

    /// The question for "example.com" IN A, sitting at the canonical offset 12.
    /// example.com encodes to 07 'example' 03 'com' 00 = 13 bytes.
    private var exampleQuestion: [UInt8] {
        var q: [UInt8] = [7]
        q.append(contentsOf: Array("example".utf8))
        q.append(3)
        q.append(contentsOf: Array("com".utf8))
        q.append(0)
        q.append(contentsOf: u16(1)) // QTYPE A
        q.append(contentsOf: u16(1)) // QCLASS IN
        return q
    }

    // MARK: Valid compression

    func testValidCompressionPointer() throws {
        // Answer name is a pointer back to the question name at offset 12.
        var packet = header(qd: 1, an: 1)
        packet.append(contentsOf: exampleQuestion)
        packet.append(contentsOf: [0xC0, 0x0C]) // pointer -> offset 12
        packet.append(contentsOf: u16(1))       // TYPE A
        packet.append(contentsOf: u16(1))       // CLASS IN
        packet.append(contentsOf: [0, 0, 0, 60]) // TTL 60
        packet.append(contentsOf: u16(4))        // RDLEN
        packet.append(contentsOf: [93, 184, 216, 34]) // 93.184.216.34

        let decoded = try DNSMessage.decode(packet)
        XCTAssertEqual(decoded.header.an, 1)
        XCTAssertEqual(decoded.answers.count, 1)
        XCTAssertEqual(decoded.answers[0].name, "example.com")
        XCTAssertEqual(decoded.answers[0].type, .a)
        XCTAssertEqual(decoded.answers[0].value, "93.184.216.34")
        XCTAssertEqual(decoded.answers[0].ttl, 60)
    }

    // MARK: Hostile pointers — must reject, never hang

    func testSelfReferentialPointerRejectedFast() {
        // Question name at offset 12 points to itself.
        var packet = header(qd: 1)
        packet.append(contentsOf: [0xC0, 0x0C]) // offset 12 -> offset 12
        packet.append(contentsOf: u16(1))
        packet.append(contentsOf: u16(1))

        let start = Date()
        XCTAssertThrowsError(try DNSMessage.decode(packet))
        // Acceptance criterion: a looped pointer fails parsing in well under 10 ms.
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.01)
    }

    func testTwoNodePointerLoopRejected() {
        // offset 12 -> 14, offset 14 -> 12: a cycle. The forward hop (14 from 12)
        // trips the strictly-backward rule before any loop can form.
        var packet = header(qd: 1)
        packet.append(contentsOf: [0xC0, 0x0E]) // offset 12 -> 14
        packet.append(contentsOf: [0xC0, 0x0C]) // offset 14 -> 12
        XCTAssertThrowsError(try DNSMessage.decode(packet))
    }

    func testForwardPointerRejected() {
        // A pointer that references a later offset must be rejected.
        var packet = header(qd: 1)
        packet.append(contentsOf: [0xC0, 0x20]) // offset 12 -> 32 (ahead)
        packet.append(contentsOf: [UInt8](repeating: 0, count: 40))
        XCTAssertThrowsError(try DNSMessage.decode(packet))
    }

    // MARK: Truncation

    func testTruncatedBitDecodes() throws {
        // TC bit set (0x0200), no answers — header must decode and report it.
        let packet = header(flags: 0x8380, qd: 0, an: 0)
        let decoded = try DNSMessage.decode(packet)
        XCTAssertTrue(decoded.header.truncated)
        XCTAssertTrue(decoded.answers.isEmpty)
    }

    func testTooShortHeaderThrows() {
        XCTAssertThrowsError(try DNSMessage.decode([0x12, 0x34, 0x81])) // < 12 bytes
    }

    func testRecordCountExceedsBodyStopsCleanly() throws {
        // ANCOUNT claims 5 but the body carries a single complete record.
        var packet = header(qd: 1, an: 5)
        packet.append(contentsOf: exampleQuestion)
        packet.append(contentsOf: [0xC0, 0x0C])
        packet.append(contentsOf: u16(1))
        packet.append(contentsOf: u16(1))
        packet.append(contentsOf: [0, 0, 0, 60])
        packet.append(contentsOf: u16(4))
        packet.append(contentsOf: [1, 2, 3, 4])

        let decoded = try DNSMessage.decode(packet) // must not loop or crash
        XCTAssertEqual(decoded.answers.count, 1)
        XCTAssertEqual(decoded.answers[0].value, "1.2.3.4")
    }

    // MARK: Malformed RDATA

    func testMalformedARDataYieldsEmptyValue() throws {
        // An A record whose RDLEN is 3, not 4 — decodeRData returns "".
        var packet = header(qd: 1, an: 1)
        packet.append(contentsOf: exampleQuestion)
        packet.append(contentsOf: [0xC0, 0x0C])
        packet.append(contentsOf: u16(1))
        packet.append(contentsOf: u16(1))
        packet.append(contentsOf: [0, 0, 0, 60])
        packet.append(contentsOf: u16(3)) // wrong length
        packet.append(contentsOf: [1, 2, 3])

        let decoded = try DNSMessage.decode(packet)
        XCTAssertEqual(decoded.answers.count, 1)
        XCTAssertEqual(decoded.answers[0].value, "")
    }

    func testRDLenBeyondBufferStopsCleanly() throws {
        // RDLEN says 40 but only a few bytes remain — the record loop must break.
        var packet = header(qd: 1, an: 1)
        packet.append(contentsOf: exampleQuestion)
        packet.append(contentsOf: [0xC0, 0x0C])
        packet.append(contentsOf: u16(1))
        packet.append(contentsOf: u16(1))
        packet.append(contentsOf: [0, 0, 0, 60])
        packet.append(contentsOf: u16(40)) // lies about the length
        packet.append(contentsOf: [1, 2, 3, 4])

        let decoded = try DNSMessage.decode(packet)
        XCTAssertTrue(decoded.answers.isEmpty)
    }

    // MARK: Name / label limits

    func testOversizedLabelRejected() {
        // A length byte of 0x40 sets a reserved high bit → invalid label.
        var packet = header(qd: 1)
        packet.append(0x40)
        packet.append(contentsOf: [UInt8](repeating: 0x61, count: 0x40))
        packet.append(0)
        packet.append(contentsOf: u16(1))
        packet.append(contentsOf: u16(1))
        XCTAssertThrowsError(try DNSMessage.decode(packet))
    }

    func testNameLongerThan255Rejected() {
        // Six 63-byte labels = 6 × 64 = 384 bytes of name, over the 255 cap.
        var name: [UInt8] = []
        for _ in 0..<6 {
            name.append(63)
            name.append(contentsOf: [UInt8](repeating: 0x61, count: 63))
        }
        name.append(0)
        var packet = header(qd: 1)
        packet.append(contentsOf: name)
        packet.append(contentsOf: u16(1))
        packet.append(contentsOf: u16(1))
        XCTAssertThrowsError(try DNSMessage.decode(packet))
    }

    // MARK: Empty answer

    func testEmptyAnswerNoError() throws {
        var packet = header(qd: 1, an: 0)
        packet.append(contentsOf: exampleQuestion)
        let decoded = try DNSMessage.decode(packet)
        XCTAssertEqual(decoded.header.rcode, 0)
        XCTAssertTrue(decoded.answers.isEmpty)
    }

    // MARK: Encoding

    func testEncodeNameRoundTrip() {
        let bytes = DNSMessage.encodeName("example.com")
        XCTAssertEqual(bytes, exampleQuestion.prefix(bytes.count).map { $0 })
        XCTAssertEqual(bytes.last, 0)
    }

    func testEncodeNameClampsOversizedLabel() {
        let long = String(repeating: "a", count: 100)
        let bytes = DNSMessage.encodeName(long)
        XCTAssertEqual(bytes.first, 63)          // clamped to the 63-byte max
        XCTAssertEqual(bytes.count, 1 + 63 + 1)  // len + 63 chars + root
    }

    func testEncodeQueryHasOptRecord() {
        let q = DNSMessage.encodeQuery(id: 0xABCD, name: "example.com", type: .a, dnssec: true)
        // ARCOUNT must be 1 (the EDNS0 OPT pseudo-record).
        XCTAssertEqual(q[10], 0)
        XCTAssertEqual(q[11], 1)
        // Decoding our own query should not throw.
        XCTAssertNoThrow(try DNSMessage.decode(q))
    }
}
