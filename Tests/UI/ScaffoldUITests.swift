import XCTest

final class ScaffoldUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launchEnvironment["MIRRORBALL_DISABLE_SIDE_EFFECTS"] = "1"
        app.launch()
        // Real e2e flows land with the UI; this proves the harness wires up.
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }
}
