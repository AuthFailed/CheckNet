import XCTest

/// The share link is untrusted input — it arrives from a scanned QR code or
/// pasted text — so decoding must reject garbage and cap the flood.
final class HostSharingTests: XCTestCase {

    // MARK: Round-trip

    func testRoundTripPreservesHosts() throws {
        let hosts = [
            SavedHost(name: "Роутер", value: "192.168.1.1", toolID: nil),
            SavedHost(name: "Cloudflare", value: "1.1.1.1", toolID: "ping"),
            SavedHost(name: "", value: "example.com", toolID: nil)
        ]
        let url = try XCTUnwrap(HostSharing.url(for: hosts))
        let decoded = try XCTUnwrap(HostSharing.hosts(from: url))
        XCTAssertEqual(decoded.map(\.value), ["192.168.1.1", "1.1.1.1", "example.com"])
        // An empty name falls back to the address.
        XCTAssertEqual(decoded.last?.name, "example.com")
        // Imported hosts land as global favorites regardless of the source scope.
        XCTAssertTrue(decoded.allSatisfy { $0.toolID == nil })
    }

    func testEmptyHostsProducesNoURL() {
        XCTAssertNil(HostSharing.url(for: []))
    }

    // MARK: Overflow

    func testDecodeCapsAtMaxHosts() throws {
        let many = (0..<(HostSharing.maxHosts + 200)).map {
            SavedHost(name: "h\($0)", value: "10.0.\($0 / 256).\($0 % 256)", toolID: nil)
        }
        let url = try XCTUnwrap(HostSharing.url(for: many))
        let decoded = try XCTUnwrap(HostSharing.hosts(from: url))
        XCTAssertEqual(decoded.count, HostSharing.maxHosts)
    }

    // MARK: Filtering hostile values

    func testImplausibleTargetsAreDropped() throws {
        let hosts = [
            SavedHost(name: "ok", value: "8.8.8.8", toolID: nil),
            SavedHost(name: "spaces", value: "not a host", toolID: nil),
            SavedHost(name: "bang", value: "example!.com", toolID: nil),
            SavedHost(name: "nodot", value: "localhostonly", toolID: nil),
            SavedHost(name: "good", value: "sub.example.com", toolID: nil)
        ]
        let url = try XCTUnwrap(HostSharing.url(for: hosts))
        let decoded = try XCTUnwrap(HostSharing.hosts(from: url))
        XCTAssertEqual(Set(decoded.map(\.value)), ["8.8.8.8", "sub.example.com"])
    }

    func testOverLongNameIsTruncated() throws {
        let hosts = [SavedHost(name: String(repeating: "x", count: 500), value: "1.1.1.1", toolID: nil)]
        let url = try XCTUnwrap(HostSharing.url(for: hosts))
        let decoded = try XCTUnwrap(HostSharing.hosts(from: url))
        XCTAssertLessThanOrEqual(decoded.first?.name.count ?? 999, 64)
    }

    // MARK: Malformed input

    func testWrongSchemeRejected() throws {
        let url = try XCTUnwrap(URL(string: "https://hosts?d=abc"))
        XCTAssertNil(HostSharing.hosts(from: url))
    }

    func testWrongActionRejected() throws {
        let url = try XCTUnwrap(URL(string: "checknet://settings?d=abc"))
        XCTAssertNil(HostSharing.hosts(from: url))
    }

    func testGarbagePayloadRejected() throws {
        let url = try XCTUnwrap(URL(string: "checknet://hosts?d=%%%not-base64%%%"))
        XCTAssertNil(HostSharing.hosts(from: url))
    }

    func testMissingPayloadRejected() throws {
        let url = try XCTUnwrap(URL(string: "checknet://hosts"))
        XCTAssertNil(HostSharing.hosts(from: url))
    }

    func testNonJSONBase64Rejected() throws {
        let junk = Data("this is not json".utf8).base64EncodedString()
        let url = try XCTUnwrap(URL(string: "checknet://hosts?d=\(junk)"))
        XCTAssertNil(HostSharing.hosts(from: url))
    }

    // MARK: Pasted text

    func testExtractsLinkFromSurroundingText() throws {
        let hosts = [SavedHost(name: "r", value: "1.1.1.1", toolID: nil)]
        let url = try XCTUnwrap(HostSharing.url(for: hosts))
        let pasted = "Смотри мой список: \(url.absoluteString) — держи!"
        let decoded = try XCTUnwrap(HostSharing.hosts(fromPastedText: pasted))
        XCTAssertEqual(decoded.first?.value, "1.1.1.1")
    }

    func testPastedTextWithoutLinkReturnsNil() {
        XCTAssertNil(HostSharing.hosts(fromPastedText: "просто текст без ссылки"))
    }
}
