import XCTest
@testable import NetworkKit

final class WorldProbeTests: XCTestCase {

    private func data(_ s: String) -> Data { Data(s.utf8) }

    // MARK: Initiate / node list

    func testParseInitiate() throws {
        let body = #"{"ok":1,"request_id":"806df9","permanent_link":"x","nodes":{"us1.node.example":["us","USA","Los Angeles","5.253.30.82","AS18978"],"ch1.node.example":["ch","Switzerland","Zurich","179.43.148.195","AS50837"]}}"#
        let parsed = try XCTUnwrap(WorldProbe.parseInitiate(data(body)))
        XCTAssertEqual(parsed.requestId, "806df9")
        XCTAssertEqual(parsed.nodes.count, 2)
        let us = try XCTUnwrap(parsed.nodes.first { $0.name == "us1.node.example" })
        XCTAssertEqual(us.countryCode, "us")
        XCTAssertEqual(us.country, "USA")
        XCTAssertEqual(us.city, "Los Angeles")
        XCTAssertEqual(us.asn, "AS18978")
        XCTAssertEqual(us.flagEmoji, "🇺🇸")
    }

    func testParseInitiateRejectsError() {
        XCTAssertNil(WorldProbe.parseInitiate(data(#"{"error":"host is required"}"#)))
    }

    func testParseNodeList() throws {
        let body = #"{"nodes":{"ru1.node.example":{"asn":"AS14576","ip":"185.159.82.88","location":["ru","Russia","Moscow"]},"de1.node.example":{"asn":"AS24940","ip":"46.4.143.48","location":["de","Germany","Falkenstein"]}}}"#
        let nodes = try XCTUnwrap(WorldProbe.parseNodeList(data(body)))
        XCTAssertEqual(nodes.count, 2)
        let ru = try XCTUnwrap(nodes.first { $0.countryCode == "ru" })
        XCTAssertEqual(ru.country, "Russia")
        XCTAssertEqual(ru.city, "Moscow")
        XCTAssertEqual(ru.asn, "AS14576")
    }

    // MARK: Ping results

    func testParsePingResults() {
        let body = #"{"us1.node.example":[[["OK",0.044,"94.242.206.94"],["TIMEOUT",3.005],["MALFORMED",0.045],["OK",0.0433]]],"ch1.node.example":[[null]],"pt1.node.example":null}"#
        let out = WorldProbe.parseResults(type: .ping, data: data(body))
        // us1: 2 OK of 4 → reachable, 50% loss, avg of the two OKs.
        let us = out["us1.node.example"]
        XCTAssertEqual(us?.status, .ok)
        XCTAssertEqual(us?.loss ?? 0, 50, accuracy: 0.01)
        XCTAssertEqual(us?.rtt ?? 0, (44 + 43.3) / 2, accuracy: 0.5)
        // ch1: [[null]] → couldn't resolve.
        XCTAssertEqual(out["ch1.node.example"]?.status, .error)
        // pt1: null → still pending, absent from the map.
        XCTAssertNil(out["pt1.node.example"])
    }

    // MARK: HTTP results

    func testParseHTTPResults() {
        let body = #"{"us1":[[1,0.13,"OK","200","94.242.206.94"]],"ch1":[[0,0.17,"Not Found","404","94.242.206.94"]],"pt1":[[0,0.07,"No such device or address",null,null]]}"#
        let out = WorldProbe.parseResults(type: .http, data: data(body))
        XCTAssertEqual(out["us1"]?.status, .ok)
        XCTAssertTrue(out["us1"]?.summary.contains("200") ?? false)
        XCTAssertEqual(out["ch1"]?.status, .failed)
        XCTAssertTrue(out["ch1"]?.summary.contains("404") ?? false)
        XCTAssertEqual(out["pt1"]?.status, .failed)
    }

    // MARK: TCP results

    func testParseTCPResults() {
        let body = #"{"us1":[{"time":0.03,"address":"104.28.31.42"}],"ch1":[{"error":"Connection timed out"}],"pt1":null}"#
        let out = WorldProbe.parseResults(type: .tcp, data: data(body))
        XCTAssertEqual(out["us1"]?.status, .ok)
        XCTAssertEqual(out["us1"]?.rtt ?? 0, 30, accuracy: 0.5)
        XCTAssertEqual(out["ch1"]?.status, .failed)
        XCTAssertEqual(out["ch1"]?.summary, "Connection timed out")
        XCTAssertNil(out["pt1"])
    }

    // MARK: DNS results

    func testParseDNSResults() {
        let body = #"{"us1":[{"A":["216.58.209.174"],"AAAA":["2a00:1450:400d:806::200e"],"TTL":299}],"ch1":[{"A":[],"AAAA":[],"TTL":null}]}"#
        let out = WorldProbe.parseResults(type: .dns, data: data(body))
        XCTAssertEqual(out["us1"]?.status, .ok)
        XCTAssertTrue(out["us1"]?.summary.contains("216.58.209.174") ?? false)
        XCTAssertEqual(out["ch1"]?.status, .failed)
    }

    func testCheckTypePaths() {
        XCTAssertEqual(WorldProbe.CheckType.ping.path, "check-ping")
        XCTAssertEqual(WorldProbe.CheckType.udp.path, "check-udp")
        XCTAssertEqual(WorldProbe.CheckType.allCases.count, 5)
    }

    // MARK: End-to-end (network)

    func testAvailableNodes() async throws {
        try requiresInternet()
        let nodes = try await WorldProbe().availableNodes()
        XCTAssertGreaterThan(nodes.count, 5, "the backend lists many nodes")
        XCTAssertTrue(nodes.allSatisfy { !$0.country.isEmpty })
        print("probe nodes: \(nodes.count), countries: \(Set(nodes.map(\.country)).count)")
    }

    func testPingFromWorld() async throws {
        try requiresInternet()
        var finished: [WorldProbeResult]?
        var failure: String?
        for await event in WorldProbe().run(type: .ping, host: "1.1.1.1", maxNodes: 8) {
            switch event {
            case .finished(let results): finished = results
            case .failed(let reason): failure = reason
            default: break
            }
        }
        if let failure { throw XCTSkip("backend unavailable: \(failure)") }
        let results = try XCTUnwrap(finished)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains { $0.status == .ok }, "some node should reach the host")
        let reachable = results.filter { $0.status == .ok }.count
        print("world ping: \(reachable)/\(results.count) reachable")
    }
}
