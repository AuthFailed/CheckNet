import XCTest
@testable import NetworkKit

final class SubscriptionParserTests: XCTestCase {
    private let vless = "vless://uuid-1234@1.2.3.4:443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=KEY&sid=SID&type=tcp&flow=xtls-rprx-vision#My%20Node"
    private let trojan = "trojan://password@5.6.7.8:8443?sni=example.org&type=ws#Trojan%20Node"

    func testParsesPlainList() {
        let r = SubscriptionParser.parse(vless + "\n" + trojan)
        XCTAssertEqual(r.format, .plainList)
        XCTAssertEqual(r.nodes.count, 2)

        let n0 = r.nodes[0]
        XCTAssertEqual(n0.proto, .vless)
        XCTAssertEqual(n0.host, "1.2.3.4")
        XCTAssertEqual(n0.port, 443)
        XCTAssertEqual(n0.security, "reality")
        XCTAssertTrue(n0.isReality)
        XCTAssertEqual(n0.sni, "www.microsoft.com")
        XCTAssertEqual(n0.flow, "xtls-rprx-vision")
        XCTAssertEqual(n0.name, "My Node")

        let n1 = r.nodes[1]
        XCTAssertEqual(n1.proto, .trojan)
        XCTAssertEqual(n1.port, 8443)
        XCTAssertEqual(n1.security, "tls")     // trojan default
        XCTAssertEqual(n1.network, "ws")
        XCTAssertEqual(n1.name, "Trojan Node")
    }

    func testParsesBase64List() {
        let list = vless + "\n" + trojan
        let b64 = Data(list.utf8).base64EncodedString()
        let r = SubscriptionParser.parse(b64)
        XCTAssertEqual(r.format, .base64List)
        XCTAssertEqual(r.nodes.count, 2)
        XCTAssertEqual(r.nodes[0].proto, .vless)
    }

    func testParsesVMess() {
        let json = "{\"v\":\"2\",\"ps\":\"VMess Node\",\"add\":\"9.9.9.9\",\"port\":\"443\",\"id\":\"uuid\",\"net\":\"ws\",\"tls\":\"tls\",\"sni\":\"cdn.example\"}"
        let link = "vmess://" + Data(json.utf8).base64EncodedString()
        let r = SubscriptionParser.parse(link)
        XCTAssertEqual(r.nodes.count, 1)
        let n = r.nodes[0]
        XCTAssertEqual(n.proto, .vmess)
        XCTAssertEqual(n.host, "9.9.9.9")
        XCTAssertEqual(n.port, 443)
        XCTAssertEqual(n.security, "tls")
        XCTAssertEqual(n.network, "ws")
        XCTAssertEqual(n.name, "VMess Node")
    }

    func testParsesShadowsocksSIP002() {
        // base64("aes-256-gcm:pass") = YWVzLTI1Ni1nY206cGFzcw
        let link = "ss://YWVzLTI1Ni1nY206cGFzcw==@3.3.3.3:8388#SS%20Node"
        let r = SubscriptionParser.parse(link)
        XCTAssertEqual(r.nodes.count, 1)
        XCTAssertEqual(r.nodes[0].proto, .shadowsocks)
        XCTAssertEqual(r.nodes[0].host, "3.3.3.3")
        XCTAssertEqual(r.nodes[0].port, 8388)
        XCTAssertEqual(r.nodes[0].name, "SS Node")
    }

    func testParsesSingBox() {
        let json = """
        {"outbounds":[
          {"type":"vless","tag":"sb-vless","server":"4.4.4.4","server_port":443,"flow":"xtls-rprx-vision","tls":{"enabled":true,"server_name":"a.com","reality":{"enabled":true}}},
          {"type":"selector","tag":"select","outbounds":["sb-vless"]},
          {"type":"trojan","tag":"sb-tr","server":"5.5.5.5","server_port":8443,"tls":{"enabled":true,"server_name":"b.com"}}
        ]}
        """
        let r = SubscriptionParser.parse(json)
        XCTAssertEqual(r.format, .singbox)
        XCTAssertEqual(r.nodes.count, 2)    // selector ignored
        XCTAssertEqual(r.nodes[0].security, "reality")
        XCTAssertEqual(r.nodes[0].sni, "a.com")
        XCTAssertEqual(r.nodes[1].proto, .trojan)
        XCTAssertEqual(r.nodes[1].port, 8443)
    }

    func testParsesClashFlowStyle() {
        let yaml = """
        proxies:
          - {name: "clash-vless", type: vless, server: 6.6.6.6, port: 443, uuid: x, tls: true, servername: c.com, network: ws, flow: xtls-rprx-vision}
          - {name: clash-ss, type: ss, server: 7.7.7.7, port: 8388, cipher: aes-256-gcm, password: p}
        """
        let r = SubscriptionParser.parse(yaml)
        XCTAssertEqual(r.format, .clash)
        XCTAssertEqual(r.nodes.count, 2)
        XCTAssertEqual(r.nodes[0].proto, .vless)
        XCTAssertEqual(r.nodes[0].host, "6.6.6.6")
        XCTAssertEqual(r.nodes[0].sni, "c.com")
        XCTAssertEqual(r.nodes[0].network, "ws")
        XCTAssertEqual(r.nodes[1].proto, .shadowsocks)
        XCTAssertEqual(r.nodes[1].port, 8388)
    }

    func testParsesXrayConfigArray() {
        // Happ/Xray subscriptions: an array of full configs, each with outbounds.
        let json = """
        [{"outbounds":[
          {"protocol":"vless","tag":"xr-vless","settings":{"vnext":[{"address":"8.8.8.8","port":443,"users":[{"id":"u","flow":"xtls-rprx-vision"}]}]},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"serverName":"www.google.com"}}},
          {"protocol":"freedom","tag":"direct"}
        ]},
        {"outbounds":[
          {"protocol":"trojan","tag":"xr-tr","settings":{"servers":[{"address":"9.9.9.9","port":8443,"password":"p"}]},"streamSettings":{"network":"ws","security":"tls","tlsSettings":{"serverName":"b.com"}}}
        ]}]
        """
        let r = SubscriptionParser.parse(json)
        XCTAssertEqual(r.format, .xray)
        XCTAssertEqual(r.nodes.count, 2)     // freedom/direct filtered out
        let v = r.nodes[0]
        XCTAssertEqual(v.proto, .vless)
        XCTAssertEqual(v.host, "8.8.8.8")
        XCTAssertEqual(v.port, 443)
        XCTAssertTrue(v.isReality)
        XCTAssertEqual(v.sni, "www.google.com")
        XCTAssertEqual(v.flow, "xtls-rprx-vision")
        XCTAssertEqual(r.nodes[1].proto, .trojan)
        XCTAssertEqual(r.nodes[1].network, "ws")
        XCTAssertEqual(r.nodes[1].sni, "b.com")
    }

    func testCapturesExtraLinkParams() {
        // fp / pbk / sid / alpn / mux / route must survive into `extras`.
        let link = "vless://id@1.2.3.4:443?security=reality&sni=a.com&type=tcp&flow=xtls-rprx-vision&fp=chrome&pbk=PUB&sid=ab12&spx=%2F&alpn=h2&mux=8&route=proxy#N"
        let n = try! XCTUnwrap(SubscriptionParser.parse(link).nodes.first)
        let map = Dictionary(uniqueKeysWithValues: n.extras.map { ($0.key, $0.value) })
        XCTAssertEqual(map["fp"], "chrome")
        XCTAssertEqual(map["pbk"], "PUB")
        XCTAssertEqual(map["sid"], "ab12")
        XCTAssertEqual(map["alpn"], "h2")
        XCTAssertEqual(map["mux"], "8")
        XCTAssertEqual(map["route"], "proxy")
        XCTAssertEqual(map["spx"], "/")            // percent-decoded
        // Headline fields are not duplicated into extras.
        XCTAssertNil(map["security"]); XCTAssertNil(map["sni"])
        XCTAssertNil(map["type"]); XCTAssertNil(map["flow"])
    }

    func testXrayNodeCarriesFullConfigAndExtras() {
        let json = """
        [{"dns":{"servers":["1.1.1.1"]},"outbounds":[
          {"protocol":"vless","tag":"p","settings":{"vnext":[{"address":"8.8.8.8","port":443,"users":[{"id":"u","flow":"xtls-rprx-vision"}]}]},
           "streamSettings":{"network":"tcp","security":"reality","realitySettings":{"serverName":"a.com","fingerprint":"chrome","publicKey":"PUB","shortId":"ab12"},"sockopt":{"tcpFastOpen":true}},
           "mux":{"enabled":false,"concurrency":8}}
        ]}]
        """
        let n = try! XCTUnwrap(SubscriptionParser.parse(json).nodes.first)
        let map = Dictionary(uniqueKeysWithValues: n.extras.map { ($0.key, $0.value) })
        XCTAssertEqual(map["streamSettings.realitySettings.fingerprint"], "chrome")
        XCTAssertEqual(map["streamSettings.realitySettings.publicKey"], "PUB")
        XCTAssertEqual(map["streamSettings.sockopt.tcpFastOpen"], "true")
        XCTAssertEqual(map["mux.concurrency"], "8")
        // The whole config for this host, not just its outbound.
        let full = try! XCTUnwrap(n.fullConfig)
        XCTAssertTrue(full.contains("\"dns\""))
        XCTAssertTrue(full.contains("\"outbounds\""))
        XCTAssertFalse(n.raw.contains("\"dns\""))   // raw stays the node's own block
    }

    func testConfigNamedByRemarksOnePerConfig() {
        // Two configs, each one server → two hosts named by their remarks.
        let json = """
        [
          {"remarks":"🇩🇪 Германия","outbounds":[
            {"protocol":"vless","tag":"proxy","settings":{"vnext":[{"address":"1.1.1.1","port":443,"users":[{"id":"u"}]}]},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"serverName":"a.com"}}},
            {"protocol":"freedom","tag":"direct"}
          ]},
          {"remarks":"🇸🇪 Швеция","outbounds":[
            {"protocol":"trojan","tag":"proxy","settings":{"servers":[{"address":"2.2.2.2","port":8443,"password":"p"}]},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"serverName":"b.com"}}}
          ]}
        ]
        """
        let r = SubscriptionParser.parse(json)
        XCTAssertEqual(r.format, .xray)
        XCTAssertEqual(r.nodes.count, 2)               // one per config, not per outbound
        XCTAssertEqual(r.nodes[0].name, "🇩🇪 Германия")
        XCTAssertEqual(r.nodes[0].host, "1.1.1.1")
        XCTAssertFalse(r.nodes[0].isMultihost)
        XCTAssertEqual(r.nodes[1].name, "🇸🇪 Швеция")
        XCTAssertEqual(r.nodes[1].proto, .trojan)
    }

    func testMultihostBundledAsOneWithChildren() {
        // One config with several proxy outbounds → a single multihost entry.
        let json = """
        [{"remarks":"🇵🇱 Польша","outbounds":[
          {"protocol":"vless","tag":"pl-1","settings":{"vnext":[{"address":"1.1.1.1","port":443,"users":[{"id":"u"}]}]},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"serverName":"a"}}},
          {"protocol":"vless","tag":"pl-2","settings":{"vnext":[{"address":"2.2.2.2","port":443,"users":[{"id":"u"}]}]},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"serverName":"b"}}},
          {"protocol":"freedom","tag":"direct"}
        ]}]
        """
        let r = SubscriptionParser.parse(json)
        XCTAssertEqual(r.nodes.count, 1)               // one row for the whole config
        let host = r.nodes[0]
        XCTAssertEqual(host.name, "🇵🇱 Польша")
        XCTAssertTrue(host.isMultihost)
        XCTAssertEqual(host.children.count, 2)         // the two inner proxies
        XCTAssertEqual(host.children.map(\.host).sorted(), ["1.1.1.1", "2.2.2.2"])
        XCTAssertEqual(host.children[0].name, "pl-1")
    }

    func testHandlesIPv6HostPort() {
        let link = "vless://id@[2001:db8::1]:443?security=tls#v6"
        let r = SubscriptionParser.parse(link)
        XCTAssertEqual(r.nodes.count, 1)
        XCTAssertEqual(r.nodes[0].host, "2001:db8::1")
        XCTAssertEqual(r.nodes[0].port, 443)
    }

    func testUnknownContent() {
        XCTAssertEqual(SubscriptionParser.parse("just some text").format, .unknown)
        XCTAssertTrue(SubscriptionParser.parse("").nodes.isEmpty)
    }
}
