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
        XCTAssertTrue(ping.waitForExistence(timeout: 30), "catalog should list Ping")

        // Existing is not the same as ready: on a loaded CI runner the list can
        // be on screen while the app is still settling, and a tap then lands on
        // nothing. Waiting for hittable keeps the assertion about navigation
        // rather than about how fast the machine is.
        let hittable = expectation(for: NSPredicate(format: "isHittable == true"),
                                   evaluatedWith: ping)
        wait(for: [hittable], timeout: 30)
        ping.tap()

        // The tool screen is the one with a host field; the catalog has none.
        let host = app.textFields.firstMatch
        XCTAssertTrue(host.waitForExistence(timeout: 15),
                      "tapping a catalog row did not open the tool screen")
    }
}
