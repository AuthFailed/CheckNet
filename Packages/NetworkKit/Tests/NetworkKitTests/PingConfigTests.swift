import XCTest
@testable import NetworkKit

/// The named `PingConfig` presets that replaced scattered magic counts.
final class PingConfigTests: XCTestCase {
    func testPresetSampleCounts() {
        XCTAssertEqual(PingConfig.preview.count, 2)
        XCTAssertEqual(PingConfig.quick.count, 3)
        XCTAssertEqual(PingConfig.standard.count, 5)
        XCTAssertEqual(PingConfig.thorough.count, 10)
    }

    func testPresetsAreOrderedBySampleCount() {
        let counts = [PingConfig.preview, .quick, .standard, .thorough].map { $0.count ?? 0 }
        XCTAssertEqual(counts, counts.sorted())
    }

    func testPayloadClampGuardsHugeValues() {
        XCTAssertEqual(PingConfig(payloadSize: 1_000_000).payloadSize, 65_500)
        XCTAssertEqual(PingConfig(payloadSize: -5).payloadSize, 0)
    }
}
