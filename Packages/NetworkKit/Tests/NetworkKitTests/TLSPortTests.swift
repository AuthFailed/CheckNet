import XCTest
@testable import NetworkKit

final class TLSPortTests: XCTestCase {
    func testPortOpen443() async throws {
        // Try several well-known HTTPS hosts; the sandbox occasionally rate-limits one.
        for host in ["8.8.8.8", "1.1.1.1", "9.9.9.9", "dns.google"] {
            let r = await PortScanner().check(host: host, port: 443, timeout: 3)
            if r.isOpen {
                XCTAssertEqual(r.serviceName, "HTTPS")
                XCTAssertNotNil(r.latencyMillis)
                return
            }
        }
        throw XCTSkip("No HTTPS control host reachable from this environment")
    }

    func testPortClosed() async {
        // Port 81 on cloudflare is filtered/closed → not open within timeout.
        let r = await PortScanner().check(host: "1.1.1.1", port: 81, timeout: 1.5)
        XCTAssertFalse(r.isOpen)
    }

    func testScanCommonPorts() async {
        var open: [Int] = []
        for await r in PortScanner().scan(host: "8.8.8.8", ports: [53, 443, 80, 22], timeout: 1.5) {
            if r.isOpen { open.append(r.port) }
        }
        print("open on 8.8.8.8: \(open.sorted())")
        XCTAssertTrue(open.contains(443))
        XCTAssertTrue(open.contains(53))
    }

    func testTLSInspectCloudflare() async throws {
        let info = try await TLSInspector().inspect(host: "cloudflare.com", port: 443)
        XCTAssertTrue(info.trustEvaluationPassed, "cloudflare.com should have a valid chain")
        XCTAssertTrue(info.negotiatedProtocol.contains("TLS"))
        XCTAssertFalse(info.certificates.isEmpty)
        let leaf = try XCTUnwrap(info.leaf)
        XCTAssertNotNil(leaf.notAfter)
        XCTAssertFalse(leaf.isExpired)
        print("TLS cloudflare.com: \(info.negotiatedProtocol) \(info.cipherSuite) alpn=\(info.alpn ?? "-") chain=\(info.certificates.count)")
        print("  leaf: \(leaf.subject) exp=\(String(describing: leaf.notAfter)) days=\(leaf.daysUntilExpiry ?? -1)")
    }

    func testTLSExpiredCert() async throws {
        // badssl provides an intentionally expired certificate.
        let info: TLSInfo
        do {
            info = try await TLSInspector().inspect(host: "expired.badssl.com", port: 443)
        } catch {
            throw XCTSkip("expired.badssl.com unreachable from this environment: \(error.localizedDescription)")
        }
        XCTAssertFalse(info.trustEvaluationPassed, "expired cert should fail trust")
        let leaf = try XCTUnwrap(info.leaf)
        print("expired.badssl.com leaf exp=\(String(describing: leaf.notAfter)) expired=\(leaf.isExpired)")
        XCTAssertTrue(leaf.isExpired)
    }
}
