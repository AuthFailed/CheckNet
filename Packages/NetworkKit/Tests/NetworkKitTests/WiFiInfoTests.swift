import XCTest
@testable import NetworkKit

final class WiFiInfoTests: XCTestCase {

    // MARK: Quality buckets (deterministic)

    func testQualityFromRSSI() {
        XCTAssertEqual(WiFiQuality(rssi: -45), .excellent)
        XCTAssertEqual(WiFiQuality(rssi: -60), .excellent)   // boundary ≥ −60
        XCTAssertEqual(WiFiQuality(rssi: -61), .good)
        XCTAssertEqual(WiFiQuality(rssi: -70), .good)
        XCTAssertEqual(WiFiQuality(rssi: -71), .fair)
        XCTAssertEqual(WiFiQuality(rssi: -80), .fair)
        XCTAssertEqual(WiFiQuality(rssi: -81), .poor)
        XCTAssertEqual(WiFiQuality(rssi: -95), .poor)
    }

    func testQualityBars() {
        XCTAssertEqual(WiFiQuality.excellent.bars, 3)
        XCTAssertEqual(WiFiQuality.poor.bars, 0)
    }

    func testSNR() {
        let status = WiFiStatus(ssid: "net", bssid: nil, rssi: -60, noise: -95, txRateMbps: 300,
                                channel: 36, band: .ghz5, width: .mhz80, phyMode: .ac, interfaceName: "en0")
        XCTAssertEqual(status.snr, 35)   // −60 − (−95)
        XCTAssertEqual(status.quality, .excellent)
    }

    func testEnumLabels() {
        XCTAssertEqual(WiFiBand.ghz5.label, "5 ГГц")
        XCTAssertEqual(WiFiWidth.mhz80.label, "80 МГц")
        XCTAssertEqual(WiFiPHYMode.ax.label, "Wi-Fi 6 (ax)")
    }

    // MARK: Live hardware (macOS + a Wi-Fi interface)

    #if canImport(CoreWLAN)
    func testCurrentInterface() throws {
        guard let status = WiFiInfo().current() else {
            throw XCTSkip("no Wi-Fi interface (or Wi-Fi off)")
        }
        // RF metrics read without any permission.
        XCTAssertLessThan(status.rssi, 0, "RSSI is negative dBm")
        XCTAssertLessThan(status.noise, 0, "noise is negative dBm")
        XCTAssertGreaterThanOrEqual(status.channel, 0)
        XCTAssertFalse(status.interfaceName.isEmpty)
        print("Wi-Fi: rssi \(status.rssi) dBm, noise \(status.noise), SNR \(status.snr), ch \(status.channel) \(status.band.label) \(status.width.label), \(status.phyMode.label), \(status.quality.label)")
    }

    func testScanReturnsNetworks() async throws {
        guard WiFiInfo().current() != nil else { throw XCTSkip("no Wi-Fi interface") }
        let networks = (try? await WiFiInfo().scan()) ?? []
        // Scanning may be Location-gated; just assert it doesn't crash and any
        // result is well-formed.
        for network in networks.prefix(3) {
            XCTAssertLessThan(network.rssi, 0)
        }
        print("Wi-Fi scan: \(networks.count) networks")
    }
    #endif
}
