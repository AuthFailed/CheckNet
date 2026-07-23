import XCTest

/// Covers the pure layer behind the host `AppEntity`: the Siri/Shortcuts picker
/// and free-typed resolution all lean on this matching, so it is tested without
/// an App Intents runtime.
final class SavedHostsPersistenceTests: XCTestCase {

    // MARK: Persistence round-trip

    private func makeDefaults() throws -> UserDefaults {
        let suite = "test.savedhosts.\(UUID().uuidString)"
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    func testLoadIsNilBeforeAnythingIsWritten() throws {
        let defaults = try makeDefaults()
        // nil, not [] — the store uses this to seed defaults only on first launch.
        XCTAssertNil(SavedHostsPersistence.load(from: defaults))
    }

    func testSaveThenLoadRoundTrips() throws {
        let defaults = try makeDefaults()
        let hosts = [
            SavedHost(name: "Роутер", value: "192.168.1.1", toolID: nil),
            SavedHost(name: "Cloudflare", value: "1.1.1.1", toolID: "ping")
        ]
        SavedHostsPersistence.save(hosts, to: defaults)
        let loaded = try XCTUnwrap(SavedHostsPersistence.load(from: defaults))
        XCTAssertEqual(loaded.map(\.value), ["192.168.1.1", "1.1.1.1"])
        XCTAssertEqual(loaded.first?.name, "Роутер")
    }

    func testEmptyListRoundTripsAsEmptyNotNil() throws {
        let defaults = try makeDefaults()
        SavedHostsPersistence.save([], to: defaults)
        // The user deleting every host is distinct from first launch.
        XCTAssertEqual(SavedHostsPersistence.load(from: defaults)?.count, 0)
    }

    // MARK: favorites()

    func testFavoritesPutGlobalBeforeScopedAndDedupes() {
        let hosts = [
            SavedHost(name: "Scoped", value: "1.1.1.1", toolID: "ping"),
            SavedHost(name: "Global", value: "8.8.8.8", toolID: nil),
            SavedHost(name: "Dup", value: "8.8.8.8", toolID: "dns")   // same address, dropped
        ]
        let fav = SavedHostMatching.favorites(hosts)
        XCTAssertEqual(fav.map(\.value), ["8.8.8.8", "1.1.1.1"])
    }

    func testFavoritesSkipBlankAddresses() {
        let hosts = [
            SavedHost(name: "Blank", value: "   ", toolID: nil),
            SavedHost(name: "Real", value: "1.1.1.1", toolID: nil)
        ]
        XCTAssertEqual(SavedHostMatching.favorites(hosts).map(\.value), ["1.1.1.1"])
    }

    // MARK: filter()

    private let sample = [
        SavedHost(name: "Дом-роутер", value: "192.168.1.1", toolID: nil),
        SavedHost(name: "Google DNS", value: "8.8.8.8", toolID: nil),
        SavedHost(name: "Cloudflare", value: "1.1.1.1", toolID: nil)
    ]

    func testEmptyQueryReturnsAllFavorites() {
        XCTAssertEqual(SavedHostMatching.filter(sample, query: "").count, 3)
        XCTAssertEqual(SavedHostMatching.filter(sample, query: "   ").count, 3)
    }

    func testFilterMatchesNameCaseInsensitively() {
        let hits = SavedHostMatching.filter(sample, query: "google")
        XCTAssertEqual(hits.map(\.value), ["8.8.8.8"])
    }

    func testFilterMatchesAddressSubstring() {
        let hits = SavedHostMatching.filter(sample, query: "192.168")
        XCTAssertEqual(hits.map(\.name), ["Дом-роутер"])
    }

    // MARK: isPlausibleHost()

    func testPlausibleAcceptsIPsAndDomains() {
        XCTAssertTrue(SavedHostMatching.isPlausibleHost("1.1.1.1"))
        XCTAssertTrue(SavedHostMatching.isPlausibleHost("2606:4700:4700::1111"))
        XCTAssertTrue(SavedHostMatching.isPlausibleHost("example.com"))
        XCTAssertTrue(SavedHostMatching.isPlausibleHost("sub.example.co.uk"))
    }

    func testPlausibleRejectsJunk() {
        XCTAssertFalse(SavedHostMatching.isPlausibleHost(""))
        XCTAssertFalse(SavedHostMatching.isPlausibleHost("google dns"))   // space
        XCTAssertFalse(SavedHostMatching.isPlausibleHost("localhost"))    // no dot, not an IP
        XCTAssertFalse(SavedHostMatching.isPlausibleHost(".com"))         // leading dot
        XCTAssertFalse(SavedHostMatching.isPlausibleHost("example."))     // trailing dot
        XCTAssertFalse(SavedHostMatching.isPlausibleHost(String(repeating: "a", count: 260) + ".com"))
    }
}
