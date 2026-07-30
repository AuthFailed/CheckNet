import XCTest
@testable import NetworkKit

final class ClientReleaseIndexTests: XCTestCase {

    // MARK: - Parsing (deterministic)

    func testParseStripsVAndDrafts() {
        let json = """
        [
          {"tag_name": "v1.9.5", "draft": false, "prerelease": false},
          {"tag_name": "1.9.4", "draft": false},
          {"tag_name": "v1.9.3-draft", "draft": true},
          {"tag_name": "v1.9.2", "draft": false}
        ]
        """.data(using: .utf8)!
        XCTAssertEqual(ClientReleaseIndex.parseVersions(json), ["1.9.5", "1.9.4", "1.9.2"])
    }

    func testParseDeduplicatesAndKeepsOrder() {
        let json = """
        [{"tag_name":"2.0.0"},{"tag_name":"v2.0.0"},{"tag_name":"1.0.0"}]
        """.data(using: .utf8)!
        XCTAssertEqual(ClientReleaseIndex.parseVersions(json), ["2.0.0", "1.0.0"])
    }

    func testParseEmptyOnGarbage() {
        XCTAssertEqual(ClientReleaseIndex.parseVersions(Data("not json".utf8)), [])
    }

    func testRepoResolvesByIDAndProduct() {
        XCTAssertEqual(ClientReleaseIndex.repo(clientID: "v2rayng"), "2dust/v2rayNG")
        XCTAssertEqual(ClientReleaseIndex.repo(product: "sing-box"), "SagerNet/sing-box")
        XCTAssertEqual(ClientReleaseIndex.repo(product: "Clash-Verge"), "clash-verge-rev/clash-verge-rev")
        XCTAssertNil(ClientReleaseIndex.repo(clientID: "shadowrocket"))   // closed source
        XCTAssertNil(ClientReleaseIndex.repo(product: "unknownApp"))
    }

    func testBadRepoThrows() async {
        do {
            _ = try await ClientReleaseIndex.versions(repo: "no-slash")
            XCTFail("expected badRepo")
        } catch ClientReleaseIndex.ReleaseError.badRepo {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Live (network-gated)

    func testLiveFetchV2rayNGVersions() async throws {
        try requiresInternet()
        let versions = try await ClientReleaseIndex.versions(repo: "2dust/v2rayNG", limit: 5)
        XCTAssertFalse(versions.isEmpty)
        // Tags look like "1.9.5" after stripping the leading v.
        XCTAssertTrue(versions.allSatisfy { $0.first?.isNumber == true })
    }
}
