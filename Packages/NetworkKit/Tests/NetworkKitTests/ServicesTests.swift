import XCTest
@testable import NetworkKit

final class ServicesTests: XCTestCase {
    // MARK: Whois

    func testWhoisDomain() async throws {
        let result = try await WhoisClient().lookup("google.com")
        XCTAssertFalse(result.raw.isEmpty)
        print("whois google.com via \(result.server); fields: \(result.fields.map { "\($0.key)=\($0.value)" })")
        // Verisign registry should identify the registrar.
        let registrar = result.value(for: "Регистратор")
        XCTAssertNotNil(registrar, "no registrar parsed")
        XCTAssertTrue(result.raw.lowercased().contains("google"))
    }

    func testWhoisReferralFollowed() async throws {
        let result = try await WhoisClient().lookup("apple.com")
        // After following referrals we should not still be on IANA.
        XCTAssertNotEqual(result.server, "whois.iana.org")
        print("apple.com whois server: \(result.server)")
    }

    // MARK: Blacklist

    func testBlacklistCleanIP() async {
        // Google DNS is not a spam source; expect no listings.
        let report = await BlacklistChecker().check(ip: "8.8.8.8",
                                                    providers: Array(BlacklistProvider.all.prefix(4)))
        print("8.8.8.8 listed \(report.listedCount)/\(report.checkedCount): " +
              report.entries.map { "\($0.provider.name)=\($0.status.rawValue)" }.joined(separator: ", "))
        XCTAssertEqual(report.entries.count, 4)
        XCTAssertEqual(report.listedCount, 0, "8.8.8.8 unexpectedly listed")
    }

    func testBlacklistReversedIP() {
        XCTAssertEqual(BlacklistChecker.reversedIPv4("1.2.3.4"), "4.3.2.1")
        XCTAssertNil(BlacklistChecker.reversedIPv4("999.1.1.1"))
        XCTAssertNil(BlacklistChecker.reversedIPv4("1.2.3"))
    }

    // MARK: Wake-on-LAN

    func testMagicPacket() throws {
        let mac = WakeOnLan.parseMAC("AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(mac, [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
        let packet = WakeOnLan.magicPacket(mac: mac!)
        XCTAssertEqual(packet.count, 6 + 16 * 6)
        XCTAssertEqual(Array(packet.prefix(6)), [UInt8](repeating: 0xFF, count: 6))
        XCTAssertEqual(Array(packet[6..<12]), [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
    }

    func testMACParsingVariants() {
        XCTAssertEqual(WakeOnLan.parseMAC("aabbccddeeff"), [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
        XCTAssertEqual(WakeOnLan.parseMAC("AA-BB-CC-DD-EE-FF"), [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
        XCTAssertNil(WakeOnLan.parseMAC("ZZ:BB:CC:DD:EE:FF"))
        XCTAssertNil(WakeOnLan.parseMAC("AA:BB:CC"))
    }

    func testWakeSendsWithoutThrowing() throws {
        // Broadcasting requires a real LAN; sandboxed CI may return "No route to host".
        // Accept a send failure, but any other error type is a real bug.
        do {
            try WakeOnLan.wake(mac: "AA:BB:CC:DD:EE:FF", broadcast: "255.255.255.255", port: 9)
        } catch WakeOnLan.WoLError.sendFailed {
            // Expected in environments without broadcast routing.
        }
    }
}
