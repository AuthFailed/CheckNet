import XCTest
@testable import NetworkKit

final class XrayReleaseTests: XCTestCase {
    private let json = """
    [
      {"tag_name":"v26.7.11","prerelease":true,"published_at":"2026-07-11T00:00:00Z","assets":[
        {"name":"Xray-macos-arm64-v8a.zip","browser_download_url":"https://x/arm64.zip","size":19612345},
        {"name":"Xray-macos-arm64-v8a.zip.dgst","browser_download_url":"https://x/arm64.zip.dgst","size":300},
        {"name":"Xray-macos-64.zip","browser_download_url":"https://x/x64.zip","size":20812345},
        {"name":"Xray-macos-64.zip.dgst","browser_download_url":"https://x/x64.zip.dgst","size":300},
        {"name":"Xray-linux-64.zip","browser_download_url":"https://x/linux.zip","size":123}
      ]},
      {"tag_name":"v26.6.27","prerelease":true,"published_at":"2026-06-27T00:00:00Z","assets":[
        {"name":"Xray-macos-arm64-v8a.zip","browser_download_url":"https://x/arm64-old.zip","size":19000000}
      ]},
      {"tag_name":"v0.0-nomacos","prerelease":false,"published_at":"2020-01-01T00:00:00Z","assets":[
        {"name":"Xray-windows-64.zip","browser_download_url":"https://x/win.zip","size":1}
      ]}
    ]
    """

    func testParsesArm64Assets() {
        let releases = XrayReleaseIndex.parse(Data(json.utf8), arch: .arm64)
        XCTAssertEqual(releases.count, 2)              // the no-macOS release is dropped
        XCTAssertEqual(releases.first?.version, "v26.7.11")
        XCTAssertTrue(releases.first?.prerelease == true)
        let asset = releases.first!.asset
        XCTAssertEqual(asset.name, "Xray-macos-arm64-v8a.zip")
        XCTAssertEqual(asset.url, "https://x/arm64.zip")
        XCTAssertEqual(asset.digestURL, "https://x/arm64.zip.dgst")
        XCTAssertEqual(asset.sizeMB, 18.7, accuracy: 0.05)
    }

    func testPicksIntelAssetForX86() {
        let releases = XrayReleaseIndex.parse(Data(json.utf8), arch: .x86_64)
        XCTAssertEqual(releases.first?.asset.name, "Xray-macos-64.zip")
        // The arm64-only older release has no x86 asset → dropped.
        XCTAssertEqual(releases.count, 1)
    }

    func testDigestParsing() {
        let hex = String(repeating: "ab", count: 32)   // 64 hex chars
        XCTAssertEqual(XrayReleaseIndex.sha256(fromDigest: "MD5= 123\nSHA2-256= \(hex)\nSHA2-512= zz"), hex)
        XCTAssertEqual(XrayReleaseIndex.sha256(fromDigest: "sha256:\(hex.uppercased())"), hex)
        XCTAssertNil(XrayReleaseIndex.sha256(fromDigest: "no hash here"))
    }
}
