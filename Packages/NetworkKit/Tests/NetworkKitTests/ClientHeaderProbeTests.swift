import XCTest
@testable import NetworkKit

final class ClientHeaderProbeTests: XCTestCase {

    // MARK: - Header parsing (deterministic)

    func testUserInfoParsesAllFields() {
        let info = ClientHeaderProbe.userInfo(from: "upload=100; download=200; total=1000; expire=1700000000")
        XCTAssertEqual(info?.uploadBytes, 100)
        XCTAssertEqual(info?.downloadBytes, 200)
        XCTAssertEqual(info?.totalBytes, 1000)
        XCTAssertEqual(info?.expire, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testUserInfoOrderIndependentAndPartial() {
        let info = ClientHeaderProbe.userInfo(from: "total=50;download=10")
        XCTAssertEqual(info?.totalBytes, 50)
        XCTAssertEqual(info?.downloadBytes, 10)
        XCTAssertNil(info?.uploadBytes)
        XCTAssertNil(info?.expire)
        XCTAssertTrue(info?.hasData ?? false)
    }

    func testUserInfoExpireZeroMeansNoExpiry() {
        let info = ClientHeaderProbe.userInfo(from: "total=1000; expire=0")
        XCTAssertEqual(info?.totalBytes, 1000)
        XCTAssertNil(info?.expire)   // 0 = never expires, not 1970.
    }

    func testUserInfoEmptyIsNil() {
        XCTAssertNil(ClientHeaderProbe.userInfo(from: ""))
        XCTAssertNil(ClientHeaderProbe.userInfo(from: nil))
        XCTAssertNil(ClientHeaderProbe.userInfo(from: "garbage-without-pairs"))
    }

    func testFilenamePlainAndQuoted() {
        XCTAssertEqual(ClientHeaderProbe.filename(from: "attachment; filename=\"my sub.yaml\""), "my sub.yaml")
        XCTAssertEqual(ClientHeaderProbe.filename(from: "attachment; filename=config.txt"), "config.txt")
    }

    func testFilenameRFC5987() {
        XCTAssertEqual(
            ClientHeaderProbe.filename(from: "attachment; filename*=UTF-8''%D0%BC%D0%BE%D1%8F.yaml"),
            "моя.yaml"
        )
    }

    func testTitlePlainAndBase64() {
        XCTAssertEqual(ClientHeaderProbe.title(from: "My VPN"), "My VPN")
        let b64 = Data("Мой профиль".utf8).base64EncodedString()
        XCTAssertEqual(ClientHeaderProbe.title(from: "base64:\(b64)"), "Мой профиль")
    }

    func testNormalizedLowercasesKeys() {
        let norm = ClientHeaderProbe.normalized(["Content-Type": "text/yaml", "Profile-Update-Interval": "24"])
        XCTAssertEqual(norm["content-type"], "text/yaml")
        XCTAssertEqual(norm["profile-update-interval"], "24")
    }

    func testDefaultClientsExcludeAuto() {
        XCTAssertFalse(ClientHeaderProbe.defaultClients.contains { $0.id == "auto" })
        XCTAssertTrue(ClientHeaderProbe.defaultClients.allSatisfy { $0.header != nil })
        XCTAssertGreaterThan(ClientHeaderProbe.defaultClients.count, 3)
    }

    // MARK: - Live (network-gated)

    func testLiveProbeReachesRealHost() async throws {
        try requiresInternet()
        // Not a real subscription, but a stable host that answers any client:
        // confirms every client request completes and the stream finishes.
        let clients = Array(ClientHeaderProbe.defaultClients.prefix(3))
        var results: [ClientProbeResult] = []
        var finishedTotal = 0
        for await event in ClientHeaderProbe.probe(urlString: "https://www.cloudflare.com/cdn-cgi/trace",
                                                   clients: clients, timeout: 10) {
            switch event {
            case .result(let r): results.append(r)
            case .finished(_, let total): finishedTotal = total
            case .failed(let m): XCTFail("probe failed: \(m)")
            }
        }
        XCTAssertEqual(results.count, clients.count)
        XCTAssertEqual(finishedTotal, clients.count)
        // Trace endpoint returns 200 for every client, though it parses to 0 nodes.
        XCTAssertTrue(results.allSatisfy { $0.statusCode == 200 })
    }

    func testInvalidURLFails() async {
        var failed = false
        for await event in ClientHeaderProbe.probe(urlString: "not a url") {
            if case .failed = event { failed = true }
        }
        XCTAssertTrue(failed)
    }
}
