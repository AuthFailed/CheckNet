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
        // Skip the first-run onboarding, which would otherwise cover the catalog
        // this test is about.
        app.launchArguments = ["-skipOnboarding"]
        app.launch()

        let ping = app.cells.staticTexts["Ping"].firstMatch
        XCTAssertTrue(ping.waitForExistence(timeout: 30), "catalog should list Ping")

        // The tool screen is the one with a host field; the catalog has none.
        let host = app.textFields.firstMatch

        // The catalog row is present, but on a loaded CI runner two things go
        // wrong that are about the machine, not the navigation: the row is on
        // screen before the app can respond, and a synthesized tap is
        // occasionally dropped entirely. So the tap is retried a few times,
        // each time waiting for the row to be hittable first. What is under
        // test — that a tap opens the tool — is unchanged; only the flake is
        // absorbed.
        for attempt in 1...4 {
            if ping.isHittable {
                ping.tap()
            }
            if host.waitForExistence(timeout: 10) {
                return
            }
            XCTContext.runActivity(named: "retry tap \(attempt)") { _ in }
        }
        XCTFail("tapping a catalog row did not open the tool screen")
    }
}
