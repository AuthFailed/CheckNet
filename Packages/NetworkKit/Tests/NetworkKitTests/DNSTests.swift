import XCTest
@testable import NetworkKit

final class DNSTests: XCTestCase {
    let client = DNSClient()

    func testAQuery() async throws {
        let res = try await client.query(name: "example.com", type: .a, resolver: "1.1.1.1")
        XCTAssertEqual(res.responseCode, .noError)
        XCTAssertFalse(res.answers.isEmpty)
        let aRecords = res.answers.filter { $0.type == .a }
        XCTAssertFalse(aRecords.isEmpty, "no A records: \(res.answers)")
        // Each A value should parse as a dotted quad.
        for r in aRecords {
            let parts = r.value.split(separator: ".")
            XCTAssertEqual(parts.count, 4, "bad A value \(r.value)")
        }
        print("A example.com via 1.1.1.1: \(aRecords.map(\.value)) in \(res.latencyMillis)ms")
    }

    func testMXQuery() async throws {
        let res = try await client.query(name: "google.com", type: .mx, resolver: "8.8.8.8")
        XCTAssertEqual(res.responseCode, .noError)
        let mx = res.answers.filter { $0.type == .mx }
        XCTAssertFalse(mx.isEmpty, "no MX: \(res.answers)")
        print("MX google.com: \(mx.map(\.value))")
    }

    func testTXTQuery() async throws {
        let res = try await client.query(name: "cloudflare.com", type: .txt, resolver: "1.1.1.1")
        XCTAssertEqual(res.responseCode, .noError)
        let txt = res.answers.filter { $0.type == .txt }
        XCTAssertFalse(txt.isEmpty)
        print("TXT cloudflare.com count=\(txt.count)")
    }

    func testAAAAQuery() async throws {
        let res = try await client.query(name: "google.com", type: .aaaa, resolver: "8.8.8.8")
        let aaaa = res.answers.filter { $0.type == .aaaa }
        XCTAssertFalse(aaaa.isEmpty, "no AAAA: \(res.answers)")
        XCTAssertTrue(aaaa.first!.value.contains(":"))
        print("AAAA google.com: \(aaaa.map(\.value))")
    }

    func testNXDomain() async throws {
        let res = try await client.query(name: "nonexistent-\(UInt32.random(in: 0...9_999_999)).invalid", type: .a, resolver: "1.1.1.1")
        XCTAssertTrue(res.responseCode == .nxDomain || res.responseCode == .noError && res.answers.isEmpty,
                      "expected NXDOMAIN, got \(res.responseCode.label)")
    }

    func testDNSSECAuthenticated() async throws {
        // cloudflare.com is DNSSEC-signed; 1.1.1.1 validates → AD bit set.
        let res = try await client.query(name: "cloudflare.com", type: .a, resolver: "1.1.1.1",
                                         options: .init(timeout: 3, dnssec: true))
        print("cloudflare.com AD bit via 1.1.1.1: \(res.authenticated)")
        XCTAssertTrue(res.authenticated, "expected DNSSEC AD bit")
    }

    func testResolverComparison() async throws {
        let rows = await client.compareResolvers(name: "wikipedia.org", type: .a,
                                                 resolvers: Array(DNSResolverInfo.presets.prefix(3)))
        XCTAssertEqual(rows.count, 3)
        for row in rows {
            print("\(row.resolver.name): \(row.result?.answers.filter { $0.type == .a }.map(\.value) ?? []) err=\(row.error ?? "-")")
        }
        XCTAssertTrue(rows.contains { ($0.result?.answers.isEmpty == false) })
    }
}
