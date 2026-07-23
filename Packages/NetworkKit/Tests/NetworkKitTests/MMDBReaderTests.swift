import XCTest
@testable import NetworkKit

final class MMDBReaderTests: XCTestCase {

    // MARK: Address → bits (deterministic)

    func testIPv4InV6DatabaseGets96LeadingZeros() {
        let bits = try? XCTUnwrap(MMDBReader.addressBits("0.0.0.1", dbVersion: 6))
        XCTAssertEqual(bits?.count, 128)
        XCTAssertEqual(bits?.prefix(96).contains(true), false)   // ::/96 mapping
        XCTAssertEqual(bits?.last, true)                          // ...0.0.0.1
    }

    func testIPv4InV4Database() {
        let bits = MMDBReader.addressBits("128.0.0.0", dbVersion: 4)
        XCTAssertEqual(bits?.count, 32)
        XCTAssertEqual(bits?.first, true)                        // MSB of 128.x
        XCTAssertEqual(bits?.dropFirst().contains(true), false)
    }

    func testIPv6Address() {
        let bits = MMDBReader.addressBits("::1", dbVersion: 6)
        XCTAssertEqual(bits?.count, 128)
        XCTAssertEqual(bits?.last, true)
        XCTAssertEqual(bits?.dropLast().contains(true), false)
    }

    func testGarbageRejected() {
        XCTAssertNil(MMDBReader.addressBits("not-an-ip", dbVersion: 6))
        XCTAssertNil(MMDBReader.addressBits("", dbVersion: 6))
    }

    func testBadDataIsNotAReader() {
        XCTAssertNil(MMDBReader(data: Data([0x00, 0x01, 0x02])))   // no metadata marker
        XCTAssertNil(MMDBReader(data: Data()))
    }

    // MARK: Against a real GeoLite2 database (network)

    func testReaderAgainstRealASNDatabase() async throws {
        try requiresInternet()
        let url = URL(string: "https://github.com/P3TERX/GeoLite.mmdb/releases/latest/download/GeoLite2-ASN.mmdb")!
        guard let (temp, response) = try? await URLSession.shared.download(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw XCTSkip("could not download GeoLite2-ASN.mmdb")
        }
        let data = try Data(contentsOf: temp)
        let reader = try XCTUnwrap(MMDBReader(data: data), "a real .mmdb should parse")

        let google = try XCTUnwrap(reader.lookup(ip: "8.8.8.8"), "8.8.8.8 must resolve in the ASN db")
        XCTAssertEqual(google["autonomous_system_number"]?.uintValue, 15169)
        let org = google["autonomous_system_organization"]?.stringValue ?? ""
        XCTAssertTrue(org.uppercased().contains("GOOGLE"), "org was \(org)")

        let cloudflare = try XCTUnwrap(reader.lookup(ip: "1.1.1.1"))
        XCTAssertEqual(cloudflare["autonomous_system_number"]?.uintValue, 13335)

        print("MMDB reader OK: 8.8.8.8 → AS\(google["autonomous_system_number"]?.uintValue ?? 0) \(org)")
    }
}
