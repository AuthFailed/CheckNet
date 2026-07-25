import XCTest
@testable import NetworkKit

final class XrayTestConfigTests: XCTestCase {
    private func obj(_ s: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: s.data(using: .utf8)!) as! [String: Any]
    }

    func testBuildsFromShareLinkReality() throws {
        let link = "vless://UUID-1@1.2.3.4:443?security=reality&sni=www.microsoft.com&type=tcp&flow=xtls-rprx-vision&fp=chrome&pbk=PUB&sid=ab12&spx=%2F#N"
        let node = try XCTUnwrap(SubscriptionParser.parse(link).nodes.first)
        let config = obj(try XrayTestConfig.build(for: node, socksPort: 10850))

        let inbound = (config["inbounds"] as! [[String: Any]])[0]
        XCTAssertEqual(inbound["protocol"] as? String, "socks")
        XCTAssertEqual(inbound["port"] as? Int, 10850)
        XCTAssertEqual(inbound["listen"] as? String, "127.0.0.1")

        let out = (config["outbounds"] as! [[String: Any]])[0]
        XCTAssertEqual(out["protocol"] as? String, "vless")
        let user = (((out["settings"] as! [String: Any])["vnext"] as! [[String: Any]])[0]["users"] as! [[String: Any]])[0]
        XCTAssertEqual(user["id"] as? String, "UUID-1")
        XCTAssertEqual(user["flow"] as? String, "xtls-rprx-vision")
        let reality = (out["streamSettings"] as! [String: Any])["realitySettings"] as! [String: Any]
        XCTAssertEqual(reality["publicKey"] as? String, "PUB")
        XCTAssertEqual(reality["shortId"] as? String, "ab12")
        XCTAssertEqual(reality["fingerprint"] as? String, "chrome")
        XCTAssertEqual(reality["serverName"] as? String, "www.microsoft.com")
    }

    func testReusesFullXrayConfigOutbound() throws {
        let json = """
        [{"dns":{"servers":["1.1.1.1"]},"routing":{"rules":[]},"outbounds":[
          {"protocol":"vless","tag":"orig","settings":{"vnext":[{"address":"9.9.9.9","port":443,"users":[{"id":"U","flow":"xtls-rprx-vision"}]}]},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"serverName":"a.com","publicKey":"K"}}},
          {"protocol":"freedom","tag":"direct"}
        ]}]
        """
        let node = try XCTUnwrap(SubscriptionParser.parse(json).nodes.first)
        let config = obj(try XrayTestConfig.build(for: node, socksPort: 1))
        let out = (config["outbounds"] as! [[String: Any]])[0]
        // The real outbound is reused verbatim (retagged proxy), freedom dropped.
        XCTAssertEqual(out["protocol"] as? String, "vless")
        XCTAssertEqual(out["tag"] as? String, "proxy")
        XCTAssertEqual((config["outbounds"] as! [[String: Any]]).count, 1)
        let reality = (out["streamSettings"] as! [String: Any])["realitySettings"] as! [String: Any]
        XCTAssertEqual(reality["publicKey"] as? String, "K")
        // No routing/dns leaks into the test config.
        XCTAssertNil(config["routing"]); XCTAssertNil(config["dns"])
    }

    func testHTTPStatusParsing() {
        XCTAssertEqual(Socks5Probe.httpStatus(Array("HTTP/1.1 204 No Content\r\n".utf8)), 204)
        XCTAssertEqual(Socks5Probe.httpStatus(Array("HTTP/1.1 200 OK\r\n".utf8)), 200)
        XCTAssertNil(Socks5Probe.httpStatus(Array("garbage".utf8)))
    }
}
