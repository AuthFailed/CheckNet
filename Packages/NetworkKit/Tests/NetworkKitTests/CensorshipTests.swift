import XCTest
@testable import NetworkKit

final class CensorshipTests: XCTestCase {
    func testDoHResolves() async throws {
        let ips = try await DoHClient().resolveA("cloudflare.com")
        print("DoH cloudflare.com: \(ips)")
        XCTAssertFalse(ips.isEmpty)
        XCTAssertTrue(ips.allSatisfy { $0.split(separator: ".").count == 4 })
    }

    func testDNSSpoofingCleanNetwork() async {
        // On an uncensored network the system resolver and DoH should agree (or overlap).
        let finding = await CensorshipChecks().checkDNSSpoofing(domain: "cloudflare.com")
        print("DNS spoof: \(finding.verdict) — \(finding.headline); \(finding.evidence)")
        XCTAssertNotEqual(finding.verdict, .restricted, "clean network should not flag DNS spoofing for cloudflare.com")
    }

    func testIPBlockingControlReachable() async {
        let finding = await CensorshipChecks().checkIPBlocking(domain: "cloudflare.com")
        print("IP block: \(finding.verdict) — \(finding.headline); \(finding.evidence)")
        // cloudflare.com is not IP-blocked anywhere sane.
        XCTAssertNotEqual(finding.verdict, .restricted)
    }

    func testSNICleanNetwork() async {
        let finding = await CensorshipChecks().checkSNIBlocking(blockedDomain: "www.wikipedia.org")
        print("SNI: \(finding.verdict) — \(finding.headline); \(finding.evidence)")
        XCTAssertNotEqual(finding.verdict, .restricted)
    }

    func testWhitelistCleanNetwork() async {
        let finding = await CensorshipChecks().checkWhitelistMode()
        print("whitelist: \(finding.verdict) — \(finding.headline); \(finding.evidence)")
        // Foreign controls are reachable here → not whitelist mode.
        XCTAssertEqual(finding.verdict, .clean)
    }

    func testHTTPBlockPageCleanNetwork() async {
        let finding = await CensorshipChecks().checkHTTPBlockPage(domain: "example.com")
        print("http block: \(finding.verdict) — \(finding.headline); \(finding.evidence)")
        XCTAssertEqual(finding.verdict, .clean)
    }
}
