import XCTest
@testable import NetworkKit

/// Deterministic tests for the hand-written X.509 / DER parser — no network.
/// Real RSA and EC fixtures are embedded as base64; every edge case (string
/// encodings, UTCTime century rule, SAN, malformed input) is exercised with
/// DER built byte-for-byte. The overriding contract: no input crashes or hangs.
final class X509ParserTests: XCTestCase {

    // MARK: DER builders

    private func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [tag]
        let n = content.count
        if n < 0x80 {
            out.append(UInt8(n))
        } else {
            var lenBytes: [UInt8] = []
            var l = n
            while l > 0 { lenBytes.insert(UInt8(l & 0xFF), at: 0); l >>= 8 }
            out.append(0x80 | UInt8(lenBytes.count))
            out.append(contentsOf: lenBytes)
        }
        out.append(contentsOf: content)
        return out
    }

    private let cnOID: [UInt8] = [0x55, 0x04, 0x03]
    private let oOID: [UInt8] = [0x55, 0x04, 0x0A]

    /// RelativeDistinguishedName holding one attribute: SET { SEQ { OID, value } }.
    private func rdn(_ oid: [UInt8], _ strTag: UInt8, _ value: [UInt8]) -> [UInt8] {
        tlv(0x31, tlv(0x30, tlv(0x06, oid) + tlv(strTag, value)))
    }

    private func name(_ rdns: [[UInt8]]) -> [UInt8] { tlv(0x30, rdns.flatMap { $0 }) }

    private func utf16be(_ s: String) -> [UInt8] {
        var out: [UInt8] = []
        for u in s.utf16 { out.append(UInt8(u >> 8)); out.append(UInt8(u & 0xFF)) }
        return out
    }

    private func utcTime(_ s: String) -> [UInt8] { tlv(0x17, Array(s.utf8)) }
    private func genTime(_ s: String) -> [UInt8] { tlv(0x18, Array(s.utf8)) }

    private func sanExtension(dns: [String] = [], ips: [[UInt8]] = []) -> [UInt8] {
        var gns: [UInt8] = []
        for d in dns { gns += tlv(0x82, Array(d.utf8)) }
        for ip in ips { gns += tlv(0x87, ip) }
        let extnValue = tlv(0x04, tlv(0x30, gns))       // OCTET STRING { GeneralNames }
        return tlv(0x30, tlv(0x06, [0x55, 0x1D, 0x11]) + extnValue)
    }

    private func caExtension() -> [UInt8] {
        tlv(0x30, tlv(0x06, [0x55, 0x1D, 0x13]) + tlv(0x01, [0xFF]))
    }

    /// A minimal but well-formed certificate reaching every field the parser reads.
    private func makeCert(issuer: [UInt8], notBefore: [UInt8], notAfter: [UInt8],
                          subject: [UInt8], ext: [UInt8] = []) -> [UInt8] {
        let version = tlv(0xA0, tlv(0x02, [0x02]))                                  // [0] v3
        let serial = tlv(0x02, [0x01, 0x23, 0x45])
        let sigAlg = tlv(0x30, tlv(0x06, [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]))
        let validity = tlv(0x30, notBefore + notAfter)
        // subjectPublicKeyInfo — skipped by the parser, scanned for extensions.
        let spki = tlv(0x30, tlv(0x06, [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]) + tlv(0x03, [0x00, 0x01]))
        let tbs = tlv(0x30, version + serial + sigAlg + issuer + validity + subject + spki + ext)
        return tlv(0x30, tbs + sigAlg + tlv(0x03, [0x00]))
    }

    private func year(of date: Date?) -> Int? {
        guard let date else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.component(.year, from: date)
    }

    // MARK: Real fixtures

    // Self-signed RSA cert: C=US/O=Example Org/CN=example.com,
    // SAN DNS example.com, www.example.com, *.example.com, IP 93.184.216.34, CA:TRUE.
    private let rsaDERBase64 = "MIIDkzCCAnugAwIBAgIUOY+elyrc9PSVzhTF+QbIUgL0bkQwDQYJKoZIhvcNAQELBQAwOTELMAkGA1UEBhMCVVMxFDASBgNVBAoMC0V4YW1wbGUgT3JnMRQwEgYDVQQDDAtleGFtcGxlLmNvbTAeFw0yNjA3MjMwNDQ1MjBaFw0yODEwMjUwNDQ1MjBaMDkxCzAJBgNVBAYTAlVTMRQwEgYDVQQKDAtFeGFtcGxlIE9yZzEUMBIGA1UEAwwLZXhhbXBsZS5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC27P6rKOXkMXNfS0H0Hdfe8El4P8GuBxkVXIlHq8c8syD+vohN1/lF7vVhG9vlgQlTdL0JEPaYRiLbXlPMt6WHI9sdPXqQWRDDHMtCVpil1VAzEcuPTKt26N1ZSYVOETUXLmOoO0vWoOhEiy5jYkruLAqv0LHA7TLeiUAsW7bzFqQC0p+lMeMGRmHl/pJ/BWHkztT0MF8eadR07PUATH7DG5HVA+Q1GCXsO5Xn0+cXTzzMkGr+JBhvt2l5d4OWBP+Udqqj6X5mgvxwOIHx8KsVwxBiLRcgkViZraTWi8c3QpJd2PWEflE/E/T8hmGT/M9I04Kr28uwfrHcx8KKMVnzAgMBAAGjgZIwgY8wHQYDVR0OBBYEFIDECgh1j86n745keMljBvvp+UQiMB8GA1UdIwQYMBaAFIDECgh1j86n745keMljBvvp+UQiMA8GA1UdEwEB/wQFMAMBAf8wPAYDVR0RBDUwM4ILZXhhbXBsZS5jb22CD3d3dy5leGFtcGxlLmNvbYINKi5leGFtcGxlLmNvbYcEXbjYIjANBgkqhkiG9w0BAQsFAAOCAQEAeapy4KhFAJylILnbi/i+3z1PzfI6QdNLl1EomUOk+O85Eo9T48q2RDaO1LC9QBigZFC4GiPkfXg9Yib5tGBdW9MibyB76kADxl7BvwpSSk9AKfONTSnUwN91psHe/Kei7m7g1EldaU7tsOb+Auy6K/DbjkNSzIzEVYAL0W6SML66p3j17r3RFAUNB6tJRZbIeIj8WYrd+hzax5J7bnOBcBr5/ebsoYtOQCd/6OVqeNImGAlqTnL9zlsLoy5UkzHO3XUSiB282S2UVNkdivlxXJV95dWfeVZTUjjkv1cLTtnvWkpwCiIzJz8jq/TPX+rNLvO2RFwJlXRjbnnztRd0BA=="

    // Self-signed EC (prime256v1) cert: C=US/O=EC Example/CN=ec.example.com, SAN ec.example.com.
    private let ecDERBase64 = "MIIB5TCCAYygAwIBAgIUcqnOFrvcsq8ZMqC7lNNHEsoUXxMwCgYIKoZIzj0EAwIwOzELMAkGA1UEBhMCVVMxEzARBgNVBAoMCkVDIEV4YW1wbGUxFzAVBgNVBAMMDmVjLmV4YW1wbGUuY29tMB4XDTI2MDcyMzA0NDUyMFoXDTI4MTAyNTA0NDUyMFowOzELMAkGA1UEBhMCVVMxEzARBgNVBAoMCkVDIEV4YW1wbGUxFzAVBgNVBAMMDmVjLmV4YW1wbGUuY29tMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEtYZOCTVSde6hgvHpnROLeCtKgLDPkaYyJiRe3nS3dyH+usS5uwJQ19chkmi5lA1nt2mj0max+/qug4d1ZJMTfKNuMGwwHQYDVR0OBBYEFAN33PKPLPGx3Mi73hG1BL6MzzMGMB8GA1UdIwQYMBaAFAN33PKPLPGx3Mi73hG1BL6MzzMGMA8GA1UdEwEB/wQFMAMBAf8wGQYDVR0RBBIwEIIOZWMuZXhhbXBsZS5jb20wCgYIKoZIzj0EAwIDRwAwRAIhAJBQEb4yW7cPvWLKaKXemZo/9NwRsdky+o2UAeEXZg8zAh8NFEFKt4QTk6mv7uVVeOOxc3LCpFzF9TISzuL6nYFg"

    private func der(_ base64: String) -> [UInt8] {
        [UInt8](Data(base64Encoded: base64)!)
    }

    // MARK: Real RSA / EC

    func testRealRSACertificate() throws {
        let fields = try XCTUnwrap(X509.parse(der: der(rsaDERBase64)))
        XCTAssertTrue(fields.subject.contains("CN=example.com"), fields.subject)
        XCTAssertTrue(fields.subject.contains("O=Example Org"), fields.subject)
        XCTAssertTrue(fields.issuer.contains("CN=example.com"), fields.issuer)
        XCTAssertTrue(fields.isCA)
        XCTAssertEqual(fields.subjectAltNames,
                       ["example.com", "www.example.com", "*.example.com", "93.184.216.34"])
        XCTAssertEqual(year(of: fields.notBefore), 2026)
        XCTAssertEqual(year(of: fields.notAfter), 2028)
    }

    func testRealECCertificate() throws {
        let fields = try XCTUnwrap(X509.parse(der: der(ecDERBase64)))
        XCTAssertTrue(fields.subject.contains("CN=ec.example.com"), fields.subject)
        XCTAssertTrue(fields.isCA)
        XCTAssertEqual(fields.subjectAltNames, ["ec.example.com"])
    }

    // MARK: String encodings

    func testUTF8StringSubject() throws {
        let cert = makeCert(issuer: name([rdn(cnOID, 0x0C, Array("Test CA".utf8))]),
                            notBefore: utcTime("260101000000Z"), notAfter: utcTime("270101000000Z"),
                            subject: name([rdn(cnOID, 0x0C, Array("Пример".utf8))]))
        let fields = try XCTUnwrap(X509.parse(der: cert))
        XCTAssertTrue(fields.subject.contains("Пример"), fields.subject)
    }

    func testPrintableAndIA5Strings() throws {
        let cert = makeCert(issuer: name([rdn(cnOID, 0x16, Array("ca.example".utf8))]),   // IA5String
                            notBefore: utcTime("260101000000Z"), notAfter: utcTime("270101000000Z"),
                            subject: name([rdn(cnOID, 0x13, Array("Example".utf8))]))      // PrintableString
        let fields = try XCTUnwrap(X509.parse(der: cert))
        XCTAssertTrue(fields.subject.contains("CN=Example"), fields.subject)
        XCTAssertTrue(fields.issuer.contains("CN=ca.example"), fields.issuer)
    }

    func testBMPStringSubject() throws {
        let cert = makeCert(issuer: name([rdn(cnOID, 0x0C, Array("CA".utf8))]),
                            notBefore: utcTime("260101000000Z"), notAfter: utcTime("270101000000Z"),
                            subject: name([rdn(cnOID, 0x1E, utf16be("Мир"))]))              // BMPString
        let fields = try XCTUnwrap(X509.parse(der: cert))
        XCTAssertTrue(fields.subject.contains("Мир"), fields.subject)
    }

    func testTeletexStringSubject() throws {
        // TeletexString read as Latin-1: 0xE9 is 'é'.
        let cert = makeCert(issuer: name([rdn(cnOID, 0x0C, Array("CA".utf8))]),
                            notBefore: utcTime("260101000000Z"), notAfter: utcTime("270101000000Z"),
                            subject: name([rdn(cnOID, 0x14, [0x43, 0x61, 0x66, 0xE9])]))    // "Café"
        let fields = try XCTUnwrap(X509.parse(der: cert))
        XCTAssertTrue(fields.subject.contains("Café"), fields.subject)
    }

    func testMultipleRDNAndCommaInValue() throws {
        // A subject value that itself contains a comma must survive intact.
        let cert = makeCert(issuer: name([rdn(cnOID, 0x0C, Array("CA".utf8))]),
                            notBefore: utcTime("260101000000Z"), notAfter: utcTime("270101000000Z"),
                            subject: name([rdn(oOID, 0x0C, Array("Acme, Inc.".utf8)),
                                           rdn(cnOID, 0x0C, Array("acme.example".utf8))]))
        let fields = try XCTUnwrap(X509.parse(der: cert))
        XCTAssertTrue(fields.subject.contains("Acme, Inc."), fields.subject)
        XCTAssertTrue(fields.subject.hasPrefix("CN=acme.example"), fields.subject)  // CN promoted first
    }

    // MARK: Time

    func testUTCTimeCenturyThreshold() throws {
        // 49 → 2049, 50 → 1950 per RFC 5280.
        let cert = makeCert(issuer: name([rdn(cnOID, 0x0C, Array("CA".utf8))]),
                            notBefore: utcTime("490101000000Z"), notAfter: utcTime("500101000000Z"),
                            subject: name([rdn(cnOID, 0x0C, Array("t".utf8))]))
        let fields = try XCTUnwrap(X509.parse(der: cert))
        XCTAssertEqual(year(of: fields.notBefore), 2049)
        XCTAssertEqual(year(of: fields.notAfter), 1950)
    }

    func testGeneralizedTime() throws {
        let cert = makeCert(issuer: name([rdn(cnOID, 0x0C, Array("CA".utf8))]),
                            notBefore: genTime("20260101000000Z"), notAfter: genTime("20500101000000Z"),
                            subject: name([rdn(cnOID, 0x0C, Array("t".utf8))]))
        let fields = try XCTUnwrap(X509.parse(der: cert))
        XCTAssertEqual(year(of: fields.notBefore), 2026)
        XCTAssertEqual(year(of: fields.notAfter), 2050)
    }

    // MARK: SAN edge cases

    func testSANWithIPv6() throws {
        let v6: [UInt8] = [0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x01]
        let cert = makeCert(issuer: name([rdn(cnOID, 0x0C, Array("CA".utf8))]),
                            notBefore: utcTime("260101000000Z"), notAfter: utcTime("270101000000Z"),
                            subject: name([rdn(cnOID, 0x0C, Array("v6.example".utf8))]),
                            ext: sanExtension(dns: ["v6.example"], ips: [v6]))
        let fields = try XCTUnwrap(X509.parse(der: cert))
        XCTAssertEqual(fields.subjectAltNames, ["v6.example", "2001:0db8:0000:0000:0000:0000:0000:0001"])
    }

    func testBasicConstraintsCAFalseByDefault() throws {
        // No BasicConstraints extension → isCA must be false.
        let cert = makeCert(issuer: name([rdn(cnOID, 0x0C, Array("CA".utf8))]),
                            notBefore: utcTime("260101000000Z"), notAfter: utcTime("270101000000Z"),
                            subject: name([rdn(cnOID, 0x0C, Array("leaf".utf8))]))
        let fields = try XCTUnwrap(X509.parse(der: cert))
        XCTAssertFalse(fields.isCA)
        XCTAssertTrue(fields.subjectAltNames.isEmpty)
    }

    func testBasicConstraintsCATrue() throws {
        let cert = makeCert(issuer: name([rdn(cnOID, 0x0C, Array("CA".utf8))]),
                            notBefore: utcTime("260101000000Z"), notAfter: utcTime("270101000000Z"),
                            subject: name([rdn(cnOID, 0x0C, Array("root".utf8))]),
                            ext: caExtension())
        let fields = try XCTUnwrap(X509.parse(der: cert))
        XCTAssertTrue(fields.isCA)
    }

    // MARK: Malformed — the crash/hang contract

    func testEmptyInput() {
        XCTAssertNil(X509.parse(der: []))
    }

    func testTruncatedRealCert() {
        // Every prefix of a real cert must parse to nil or Fields, never crash.
        let full = der(rsaDERBase64)
        for cut in stride(from: 1, to: full.count, by: 7) {
            _ = X509.parse(der: Array(full.prefix(cut)))
        }
    }

    func testLengthExceedsBuffer() {
        // SEQUENCE claiming 0xFFFF bytes in a 4-byte buffer.
        XCTAssertNil(X509.parse(der: [0x30, 0x82, 0xFF, 0xFF]))
    }

    func testDeeplyNestedDoesNotHang() {
        // 2000 nested SEQUENCE headers: the parser must terminate, not overflow.
        var payload: [UInt8] = tlv(0x02, [0x00])
        for _ in 0..<2000 { payload = tlv(0x30, payload) }
        let start = Date()
        _ = X509.parse(der: payload)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }

    func testRandomFuzzNeverCrashes() {
        // A fixed pseudo-random sweep (deterministic seed) as a smoke fuzz.
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next() -> UInt8 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return UInt8((state >> 33) & 0xFF)
        }
        for len in [0, 1, 4, 16, 64, 200] {
            for _ in 0..<50 {
                let bytes = (0..<len).map { _ in next() }
                _ = X509.parse(der: bytes) // must not crash or hang
            }
        }
    }
}
