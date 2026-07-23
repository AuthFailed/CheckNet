import XCTest

/// The UserDefaults JSON helpers that collapsed five copy-pasted
/// encode/decode implementations.
final class CodableDefaultsTests: XCTestCase {
    private let suite = "test.checknet.codabledefaults"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private struct Item: Codable, Equatable { var name: String; var count: Int }

    func testRoundTrip() {
        let value = [Item(name: "a", count: 1), Item(name: "b", count: 2)]
        defaults.setJSON(value, forKey: "items")
        XCTAssertEqual(defaults.json([Item].self, forKey: "items"), value)
    }

    func testMissingKeyReturnsNil() {
        XCTAssertNil(defaults.json([Item].self, forKey: "absent"))
    }

    func testOverwrite() {
        defaults.setJSON([Item(name: "a", count: 1)], forKey: "items")
        defaults.setJSON([Item(name: "z", count: 9)], forKey: "items")
        XCTAssertEqual(defaults.json([Item].self, forKey: "items"), [Item(name: "z", count: 9)])
    }

    func testTypeMismatchReturnsNil() {
        defaults.setJSON(Item(name: "a", count: 1), forKey: "items")   // an object…
        XCTAssertNil(defaults.json([Item].self, forKey: "items"))      // …decoded as an array
    }

    func testCorruptDataReturnsNil() {
        defaults.set(Data([0x00, 0x01, 0x02]), forKey: "items")
        XCTAssertNil(defaults.json([Item].self, forKey: "items"))
    }
}
