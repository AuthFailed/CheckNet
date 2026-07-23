import XCTest

/// The Handoff payload is written on one device and read on another, so the
/// codec is pinned by tests. The merge feeds both QR import and iCloud sync.
final class ToolActivityTests: XCTestCase {

    // MARK: Handoff payload

    func testUserInfoRoundTripsWithHost() {
        let info = ToolActivity.userInfo(toolRawValue: "ping", host: "1.1.1.1")
        XCTAssertEqual(ToolActivity.payload(from: info),
                       ToolActivity.Payload(toolRawValue: "ping", host: "1.1.1.1"))
    }

    func testUserInfoDropsEmptyHost() {
        let info = ToolActivity.userInfo(toolRawValue: "dns", host: "   ")
        XCTAssertEqual(ToolActivity.payload(from: info),
                       ToolActivity.Payload(toolRawValue: "dns", host: nil))
    }

    func testPayloadRejectsMissingTool() {
        XCTAssertNil(ToolActivity.payload(from: ["host": "1.1.1.1"]))
        XCTAssertNil(ToolActivity.payload(from: nil))
        XCTAssertNil(ToolActivity.payload(from: ["tool": ""]))
    }

    // MARK: Merge

    func testUnionKeepsBothAndDedupesByAddress() {
        let local = [
            SavedHost(name: "Роутер", value: "192.168.1.1", toolID: nil),
            SavedHost(name: "CF", value: "1.1.1.1", toolID: nil)
        ]
        let remote = [
            SavedHost(name: "Cloudflare", value: "1.1.1.1", toolID: nil),   // dup by address
            SavedHost(name: "Google", value: "8.8.8.8", toolID: nil)        // new
        ]
        let merged = SavedHostMerge.union(local, remote)
        XCTAssertEqual(merged.map(\.value), ["192.168.1.1", "1.1.1.1", "8.8.8.8"])
        // Local name wins on a clash — a remote device never renames your host.
        XCTAssertEqual(merged.first { $0.value == "1.1.1.1" }?.name, "CF")
    }

    func testUnionCaseInsensitiveOnAddress() {
        let a = [SavedHost(name: "A", value: "Example.com", toolID: nil)]
        let b = [SavedHost(name: "B", value: "example.com", toolID: nil)]
        XCTAssertEqual(SavedHostMerge.union(a, b).count, 1)
    }

    func testUnionKeepsGlobalAndScopedApart() {
        let a = [SavedHost(name: "Global", value: "1.1.1.1", toolID: nil)]
        let b = [SavedHost(name: "Scoped", value: "1.1.1.1", toolID: "ping")]
        // Same address, different scope: both survive.
        XCTAssertEqual(SavedHostMerge.union(a, b).count, 2)
    }

    func testUnionSkipsBlankAddresses() {
        let a = [SavedHost(name: "Blank", value: "  ", toolID: nil)]
        let b = [SavedHost(name: "Real", value: "9.9.9.9", toolID: nil)]
        XCTAssertEqual(SavedHostMerge.union(a, b).map(\.value), ["9.9.9.9"])
    }
}
