import XCTest
@testable import NetworkKit

final class JA3Tests: XCTestCase {
    /// A deterministic RNG so the byte structure is reproducible in tests.
    struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    // MARK: - ClientHello structure

    func testClientHelloIsWellFormed() {
        for profile in JA3Profile.allCases {
            var rng = SeededRNG(state: 42)
            let hello = ClientHelloBuilder(profile: profile, serverName: "example.com").build(using: &rng)

            // Record header: handshake, TLS 1.0 record version.
            XCTAssertEqual(hello[0], 0x16, "\(profile): record type must be handshake")
            XCTAssertEqual(hello[1], 0x03)
            XCTAssertEqual(hello[2], 0x01)

            let recordLen = (Int(hello[3]) << 8) | Int(hello[4])
            XCTAssertEqual(recordLen, hello.count - 5, "\(profile): record length must match body")

            // Handshake header: client_hello, 3-byte length.
            XCTAssertEqual(hello[5], 0x01, "\(profile): handshake type must be client_hello")
            let hsLen = (Int(hello[6]) << 16) | (Int(hello[7]) << 8) | Int(hello[8])
            XCTAssertEqual(hsLen, hello.count - 9, "\(profile): handshake length must match body")

            // legacy_version inside body.
            XCTAssertEqual(hello[9], 0x03)
            XCTAssertEqual(hello[10], 0x03, "\(profile): legacy_version must be TLS 1.2")
        }
    }

    func testServerNameIsPresentInBytes() {
        var rng = SeededRNG(state: 7)
        let hello = ClientHelloBuilder(profile: .chrome, serverName: "rutracker.org").build(using: &rng)
        // The SNI hostname must appear verbatim in the emitted bytes.
        let needle = Array("rutracker.org".utf8)
        XCTAssertTrue(hello.containsSubsequence(needle), "SNI hostname must be embedded in the ClientHello")
    }

    func testProfilesProduceDistinctBytes() {
        var r1 = SeededRNG(state: 1)
        var r2 = SeededRNG(state: 1)
        var r3 = SeededRNG(state: 1)
        let chrome = ClientHelloBuilder(profile: .chrome, serverName: "a.com").build(using: &r1)
        let firefox = ClientHelloBuilder(profile: .firefox, serverName: "a.com").build(using: &r2)
        let safari = ClientHelloBuilder(profile: .safari, serverName: "a.com").build(using: &r3)
        XCTAssertNotEqual(chrome, firefox, "Chrome and Firefox handshakes must differ")
        XCTAssertNotEqual(chrome, safari)
        XCTAssertNotEqual(firefox, safari)
        // Firefox emits no GREASE cipher, so its ClientHello is smaller here.
        XCTAssertGreaterThan(chrome.count, 100)
    }

    // MARK: - Live probes

    func testEveryProfileGetsServerHello() async throws {
        try requiresInternet()
        for profile in JA3Profile.allCases {
            let result = await JA3Probe().run(host: "github.com", profile: profile)
            print("\(profile.rawValue) → \(result.reaction.label) [\(Int(result.elapsedMillis)) ms, \(result.bytesReceived) B]")
            XCTAssertTrue(result.tcpConnected, "\(profile): TCP should connect to github.com")
            XCTAssertEqual(result.reaction, .serverHello,
                           "\(profile): a real browser handshake must be accepted on a clean network")
        }
    }

    /// The SNI is independent of the connection endpoint — the property that
    /// makes this usable for SNI-blocking tests.
    func testCustomSNIStillHandshakes() async throws {
        try requiresInternet()
        let result = await JA3Probe().run(host: "github.com", serverName: "example.com", profile: .chrome)
        print("custom SNI → \(result.reaction.label)")
        XCTAssertTrue(result.tcpConnected)
        // github's edge answers ClientHellos for arbitrary SNI (ServerHello or alert),
        // both of which prove the ClientHello reached it.
        XCTAssertFalse(result.reaction.suggestsInterference,
                       "reaching the server, even with a foreign SNI, is not interference")
    }

    func testTCPFailureIsNotInterference() async throws {
        try requiresInternet()
        // Port 9 (discard) is closed on github's edge → TCP never establishes.
        let result = await JA3Probe().run(host: "github.com", profile: .chrome, port: 9, connectTimeout: 4)
        print("closed port → \(result.reaction.label)")
        XCTAssertEqual(result.reaction, .tcpFailed)
        XCTAssertFalse(result.reaction.suggestsInterference)
    }
}

private extension Array where Element == UInt8 {
    func containsSubsequence(_ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, count >= needle.count else { return false }
        for start in 0...(count - needle.count) where Array(self[start..<start + needle.count]) == needle {
            return true
        }
        return false
    }
}
