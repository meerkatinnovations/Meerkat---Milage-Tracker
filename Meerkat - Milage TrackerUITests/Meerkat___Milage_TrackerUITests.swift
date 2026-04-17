import XCTest

final class MeerkatMilageTrackerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTabsExist() throws {
        let app = XCUIApplication()
        app.launch()

        let tripsTab = app.tabBars.buttons["Trips"]
        if tripsTab.waitForExistence(timeout: 2) {
            XCTAssertTrue(app.tabBars.buttons["Fuel"].exists)
            XCTAssertTrue(app.tabBars.buttons["Maintenance"].exists)
            XCTAssertTrue(app.tabBars.buttons["Logs"].exists)
            XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
            return
        }

        XCTAssertTrue(
            app.buttons["Continue To Subscription"].waitForExistence(timeout: 2) ||
            app.buttons["Unlock with Face ID"].waitForExistence(timeout: 2) ||
            app.buttons["Unlock with Touch ID"].waitForExistence(timeout: 2),
            "Expected either the main tab bar or an initial access screen."
        )
    }
}
