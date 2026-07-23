import XCTest
@testable import NetworkKit

/// Smoke tests for the small support primitives that had no direct coverage.
final class SupportTests: XCTestCase {

    // MARK: MonoClock

    func testMonoClockIsMonotonic() {
        let a = MonoClock.nanos()
        let b = MonoClock.nanos()
        XCTAssertGreaterThanOrEqual(b, a, "monotonic clock went backwards")
    }

    func testMonoClockMillisSinceIsNonNegative() {
        let start = MonoClock.nanos()
        var acc: UInt64 = 0
        for i in 0..<10_000 { acc &+= UInt64(i) }
        XCTAssertGreaterThanOrEqual(MonoClock.millisSince(start), 0)
        XCTAssertEqual(acc, 49_995_000)   // keep the loop from being optimised away
    }

    // MARK: NetworkError

    func testNetworkErrorDescriptionsAreLocalisedAndNonEmpty() {
        let cases: [NetworkError] = [
            .invalidHost("x"), .resolutionFailed(host: "h", reason: "r"),
            .socketCreationFailed(reason: "r"), .socketOptionFailed(reason: "r"),
            .sendFailed(reason: "r"), .timedOut, .cancelled,
            .notSupported("m"), .tls("m"), .protocolError("m")
        ]
        for error in cases {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error) has no description")
        }
    }

    func testNetworkErrorInterpolatesAssociatedValues() {
        XCTAssertEqual(NetworkError.invalidHost("1.2.3.4").errorDescription, "Некорректный хост: 1.2.3.4")
        XCTAssertEqual(NetworkError.resolutionFailed(host: "example.com", reason: "таймаут").errorDescription,
                       "Не удалось разрешить example.com: таймаут")
    }

    func testNetworkErrorEquatable() {
        XCTAssertEqual(NetworkError.timedOut, .timedOut)
        XCTAssertNotEqual(NetworkError.timedOut, .cancelled)
        XCTAssertEqual(NetworkError.tls("a"), .tls("a"))
        XCTAssertNotEqual(NetworkError.tls("a"), .tls("b"))
    }

    // MARK: IPFamily

    func testIPFamilyRoundTrips() {
        XCTAssertEqual(IPFamily(rawValue: "ipv4"), .ipv4)
        XCTAssertEqual(IPFamily(rawValue: "ipv6"), .ipv6)
        XCTAssertNil(IPFamily(rawValue: "ipv7"))
    }
}
