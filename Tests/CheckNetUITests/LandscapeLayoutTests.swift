import XCTest

/// Landscape layout on a phone, which is the one case a plain unit test cannot
/// reach: the size classes only change when the device actually rotates.
///
/// It matters most on a Pro Max, which reports a *regular* horizontal size class
/// in landscape. Asking about width first put that device into the iPad
/// arrangement — three columns on a 430 pt-tall screen — so these tests pin the
/// rule that compact height wins.
final class LandscapeLayoutTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    private func launchPing() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-openTool", "ping", "-host", "1.1.1.1"]
        app.launch()
        return app
    }

    /// In landscape the catalog must not open a sidebar: it would spend width
    /// the tool needs, and there is no vertical room to spare either.
    func testLandscapeKeepsCatalogSingleColumn() {
        let app = launchPing()
        XCUIDevice.shared.orientation = .landscapeLeft
        let host = app.textFields.firstMatch
        XCTAssertTrue(host.waitForExistence(timeout: 10), "host field should be on screen in landscape")

        // The tool screen fills the window; the catalog list is not beside it.
        let catalogSearch = app.searchFields.firstMatch
        XCTAssertFalse(catalogSearch.exists,
                       "catalog search means a sidebar is open next to the tool")

        attachScreenshot(app, name: "landscape-ping")
    }

    /// The run button travels with the input in the rail rather than sitting in
    /// a bar pinned across the bottom, which in landscape costs a fifth of the
    /// screen and collides with the tab bar.
    ///
    /// Matched by accessibility identifier, not by label: the label is
    /// translated into 13 languages and a simulator running English would fail
    /// a test written against the Russian text.
    func testRunButtonSitsBesideTheInputNotUnderTheTabBar() {
        let app = launchPing()
        XCUIDevice.shared.orientation = .landscapeLeft

        let host = app.textFields.firstMatch
        XCTAssertTrue(host.waitForExistence(timeout: 10))

        let run = app.buttons["tool.runButton"].firstMatch
        guard run.waitForExistence(timeout: 5) else {
            attachScreenshot(app, name: "landscape-no-run-button")
            return XCTFail("run button not found in landscape")
        }

        // Same column as the input, not stretched across the window.
        XCTAssertLessThan(run.frame.width, app.frame.width * 0.6,
                          "run button spans the window — it is still a bottom bar")
        XCTAssertLessThan(abs(run.frame.midX - host.frame.midX), 40,
                          "run button is not in the same column as the input")

        attachScreenshot(app, name: "landscape-rail")
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
