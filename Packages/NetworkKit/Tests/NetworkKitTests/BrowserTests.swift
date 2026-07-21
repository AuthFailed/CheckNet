import XCTest
@testable import NetworkKit

final class BrowserTests: XCTestCase {
    func testMACVendorLookup() {
        XCTAssertEqual(MACVendor.lookup(mac: "A4:83:E7:11:22:33"), "Apple")
        XCTAssertEqual(MACVendor.lookup(mac: "b8-27-eb-aa-bb-cc"), "Raspberry Pi")
        XCTAssertEqual(MACVendor.lookup(mac: "18:FE:34:00:00:01"), "Espressif (ESP)")
        XCTAssertNil(MACVendor.lookup(mac: "ZZ:ZZ:ZZ:00:00:00"))
    }

    func testRandomizedMAC() {
        // 2nd-least-significant bit of first octet set → locally administered.
        XCTAssertTrue(MACVendor.isRandomized(mac: "A2:00:00:00:00:00"))  // 0xA2 & 0x02 = 2
        XCTAssertFalse(MACVendor.isRandomized(mac: "A4:83:E7:00:00:00")) // 0xA4 & 0x02 = 0
    }

    func testPrimaryCIDR() {
        let cidr = NetworkInterfaces.primaryIPv4CIDR()
        print("primary CIDR: \(cidr ?? "nil")")
        if let cidr {
            XCTAssertTrue(cidr.hasSuffix("/24"))
            XCTAssertNotNil(IPv4Range.hosts(from: cidr))
        }
    }

    func testARPReadable() {
        // Not asserting contents (environment-dependent), just that it doesn't crash.
        let entries = ARPTable.entries()
        print("ARP entries: \(entries.count)")
        for (ip, mac) in entries.prefix(5) { print("  \(ip) -> \(mac) [\(MACVendor.lookup(mac: mac) ?? "?")]") }
    }

    func testBrowseSmallRange() async throws {
        try requiresInternet()
        // Browse the two Cloudflare anycast IPs as a fixed range (fast, deterministic).
        var devices: [DiscoveredDevice] = []
        for await event in NetworkBrowser().browse(cidr: "1.1.1.1-1.1.1.1", timeout: 2.0) {
            if case .device(let d) = event { devices.append(d) }
        }
        XCTAssertTrue(devices.contains { $0.ip == "1.1.1.1" })
    }
}
