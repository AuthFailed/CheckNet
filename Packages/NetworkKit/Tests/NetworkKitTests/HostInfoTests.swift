import XCTest
@testable import NetworkKit

final class HostInfoTests: XCTestCase {
    func testReverseDNS() async throws {
        try requiresInternet()
        let name = try await ReverseDNS.lookup(ip: "8.8.8.8")
        print("PTR 8.8.8.8 -> \(name ?? "nil")")
        XCTAssertNotNil(name)
        XCTAssertTrue(name?.contains("dns.google") ?? false, "got \(name ?? "nil")")
    }

    func testHostToIP() async throws {
        try requiresInternet()
        let result = try await HostLookup.resolve(host: "one.one.one.one", family: .ipv4)
        XCTAssertTrue(result.addresses.contains { $0.ip == "1.1.1.1" || $0.ip == "1.0.0.1" })
    }

    func testInterfaces() {
        let ifaces = NetworkInterfaces.list(includeLoopback: true)
        XCTAssertFalse(ifaces.isEmpty)
        XCTAssertTrue(ifaces.contains { $0.isLoopback && $0.address.hasPrefix("127.") })
        print("interfaces: \(ifaces.map { "\($0.name)=\($0.address)" }.prefix(8))")
    }
}
