import XCTest
@testable import NetworkKit

final class RealitySNICheckTests: XCTestCase {

    // MARK: - Pure logic (deterministic, always runs in CI)

    private func cert(subject: String, issuer: String, sans: [String],
                      notAfter: Date? = Date().addingTimeInterval(60 * 86_400)) -> TLSCertificate {
        TLSCertificate(
            subject: subject, issuer: issuer,
            notBefore: Date().addingTimeInterval(-86_400), notAfter: notAfter,
            serialNumber: "01", sha256Fingerprint: "AA", isCA: false, subjectAltNames: sans
        )
    }

    private func info(protocol proto: String, alpn: String?, trust: Bool,
                      leaf: TLSCertificate?) -> TLSInfo {
        TLSInfo(
            host: "www.example.com", port: 443, resolvedIP: "93.184.216.34",
            negotiatedProtocol: proto, cipherSuite: "TLS_AES_128_GCM_SHA256",
            alpn: alpn, handshakeMillis: 42, trustEvaluationPassed: trust,
            certificates: leaf.map { [$0] } ?? []
        )
    }

    func testIdealTargetPasses() {
        let leaf = cert(subject: "CN=www.example.com", issuer: "CN=R3, O=Let's Encrypt",
                        sans: ["www.example.com", "example.com"])
        let report = RealitySNICheck.evaluate(
            host: "www.example.com", port: 443,
            info: info(protocol: "TLS 1.3", alpn: "h2", trust: true, leaf: leaf),
            supportsX25519: true, redirectLocation: nil
        )
        XCTAssertEqual(report.verdict, .pass)
        XCTAssertTrue(report.criteria.filter(\.isRequired).allSatisfy { $0.grade == .pass })
        XCTAssertTrue(report.sniCoveredByCert)
    }

    func testTLS12IsHardFail() {
        let leaf = cert(subject: "CN=old.example.com", issuer: "O=CA", sans: ["old.example.com"])
        let report = RealitySNICheck.evaluate(
            host: "old.example.com", port: 443,
            info: info(protocol: "TLS 1.2", alpn: "h2", trust: true, leaf: leaf),
            supportsX25519: true, redirectLocation: nil
        )
        XCTAssertEqual(report.verdict, .fail)
        XCTAssertEqual(report.criteria.first { $0.key == "tls13" }?.grade, .fail)
    }

    func testMissingH2IsHardFail() {
        let leaf = cert(subject: "CN=h1.example.com", issuer: "O=CA", sans: ["h1.example.com"])
        let report = RealitySNICheck.evaluate(
            host: "h1.example.com", port: 443,
            info: info(protocol: "TLS 1.3", alpn: "http/1.1", trust: true, leaf: leaf),
            supportsX25519: true, redirectLocation: nil
        )
        XCTAssertEqual(report.verdict, .fail)
        XCTAssertEqual(report.criteria.first { $0.key == "h2" }?.grade, .fail)
    }

    func testExternalRedirectOnlyWarns() {
        let leaf = cert(subject: "CN=redir.example.com", issuer: "O=CA", sans: ["redir.example.com"])
        let report = RealitySNICheck.evaluate(
            host: "redir.example.com", port: 443,
            info: info(protocol: "TLS 1.3", alpn: "h2", trust: true, leaf: leaf),
            supportsX25519: true, redirectLocation: "somewhere-else.com"
        )
        XCTAssertEqual(report.verdict, .warn)   // required all pass, soft warns
        XCTAssertEqual(report.criteria.first { $0.key == "redirect" }?.grade, .warn)
    }

    func testNoX25519Warns() {
        let leaf = cert(subject: "CN=nox.example.com", issuer: "O=CA", sans: ["nox.example.com"])
        let report = RealitySNICheck.evaluate(
            host: "nox.example.com", port: 443,
            info: info(protocol: "TLS 1.3", alpn: "h2", trust: true, leaf: leaf),
            supportsX25519: false, redirectLocation: nil
        )
        XCTAssertEqual(report.verdict, .warn)
        XCTAssertEqual(report.criteria.first { $0.key == "x25519" }?.grade, .warn)
    }

    // MARK: - Host / cert matching

    func testWildcardCoversOneLabelOnly() {
        let leaf = cert(subject: "CN=*.example.com", issuer: "O=CA", sans: ["*.example.com"])
        XCTAssertTrue(RealitySNICheck.certCovers(host: "www.example.com", cert: leaf))
        XCTAssertFalse(RealitySNICheck.certCovers(host: "a.b.example.com", cert: leaf))
        XCTAssertFalse(RealitySNICheck.certCovers(host: "example.com", cert: leaf))
    }

    func testRedirectTargetIgnoresWWWBounce() {
        let head = "HTTP/1.1 301 Moved Permanently\r\nLocation: https://www.example.com/\r\n"
        XCTAssertNil(RealitySNICheck.redirectTarget(head, host: "example.com"))
    }

    func testRedirectTargetReportsExternalHost() {
        let head = "HTTP/1.1 302 Found\r\nLocation: https://cdn.other.net/x\r\n"
        XCTAssertEqual(RealitySNICheck.redirectTarget(head, host: "example.com"), "cdn.other.net")
    }

    func testNon3xxIsNoRedirect() {
        let head = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n"
        XCTAssertNil(RealitySNICheck.redirectTarget(head, host: "example.com"))
    }

    // MARK: - Live (network-gated)

    func testLiveMicrosoftIsAGoodTarget() async throws {
        try requiresInternet()
        let report = await RealitySNICheck().run(host: "www.microsoft.com")
        XCTAssertEqual(report.tlsVersion, "TLS 1.3")
        XCTAssertEqual(report.alpn, "h2")
        XCTAssertFalse(report.certSubject.isEmpty)
        XCTAssertTrue(report.supportsX25519)
        // Microsoft's front is a textbook Reality dest — required criteria must all pass.
        XCTAssertNotEqual(report.verdict, .fail)
        XCTAssertTrue(report.criteria.filter(\.isRequired).allSatisfy { $0.grade == .pass })
    }

    func testLiveUnreachableHostFailsCleanly() async throws {
        try requiresInternet()
        let report = await RealitySNICheck().run(host: "no-such-host.invalid", timeout: 4)
        XCTAssertEqual(report.verdict, .fail)
    }
}
