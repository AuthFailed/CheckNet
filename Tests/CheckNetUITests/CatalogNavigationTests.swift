import XCTest

/// Opening a tool from the catalog is the app's first interaction, and it is
/// the one thing no unit test can stand in for: it goes through a real List row
/// and a real navigation stack.
final class CatalogNavigationTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTappingACatalogRowOpensTheTool() {
        let app = XCUIApplication()
        app.launch()

        let ping = app.cells.staticTexts["Ping"].firstMatch
        XCTAssertTrue(ping.waitForExistence(timeout: 10), "catalog should list Ping")
        ping.tap()

        // The tool screen is the one with a host field; the catalog has none.
        let host = app.textFields.firstMatch
        XCTAssertTrue(host.waitForExistence(timeout: 5),
                      "tapping a catalog row did not open the tool screen")
    }
}
