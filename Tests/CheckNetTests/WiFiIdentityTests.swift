import XCTest

final class WiFiIdentityTests: XCTestCase {

    func testBSSIDZeroPadsAndLowercases() {
        let info = WiFiIdentity(ssid: "Home", bssid: "0:23:A:bC:5:F")
        XCTAssertEqual(info.bssidDisplay, "00:23:0a:bc:05:0f")
    }

    func testBSSIDAlreadyNormalisedStaysStable() {
        let info = WiFiIdentity(ssid: "Home", bssid: "00:23:0a:bc:05:0f")
        XCTAssertEqual(info.bssidDisplay, "00:23:0a:bc:05:0f")
    }

    func testBSSIDNonStandardIsLowercasedNotReformatted() {
        // Not six octets — don't invent structure, just lowercase.
        let info = WiFiIdentity(ssid: "Home", bssid: "AA-BB-CC")
        XCTAssertEqual(info.bssidDisplay, "aa-bb-cc")
    }

    func testBlankBSSIDBecomesNil() {
        XCTAssertNil(WiFiIdentity(ssid: "Home", bssid: "   ").bssidDisplay)
        XCTAssertNil(WiFiIdentity(ssid: "Home", bssid: "").bssid)
        XCTAssertNil(WiFiIdentity(ssid: "Home", bssid: nil).bssid)
    }

    func testIsSecureFollowsSecurityType() {
        XCTAssertFalse(WiFiIdentity(ssid: "Cafe", security: .open).isSecure)
        XCTAssertTrue(WiFiIdentity(ssid: "Home", security: .personal).isSecure)
        XCTAssertTrue(WiFiIdentity(ssid: "Corp", security: .enterprise).isSecure)
        XCTAssertTrue(WiFiIdentity(ssid: "Old", security: .wep).isSecure)
        // Unknown is treated as "not proven open" → secure side.
        XCTAssertTrue(WiFiIdentity(ssid: "X", security: .unknown).isSecure)
    }

    func testSecurityLabelsAreDistinct() {
        let all: [WiFiIdentity.Security] = [.open, .wep, .personal, .enterprise, .unknown]
        let labels = all.map { WiFiIdentity(ssid: "n", security: $0).securityLabel }
        XCTAssertEqual(Set(labels).count, all.count, "each security type needs its own label")
    }
}
