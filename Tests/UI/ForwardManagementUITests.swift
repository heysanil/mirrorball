import XCTest

/// End-to-end flows driving the real app through the accessibility tree, with a
/// fake-ssh harness so connection state is deterministic.
final class ForwardManagementUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        // Reap any lingering fake-ssh children if the app was force-killed.
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        kill.arguments = ["-f", "sleep 100000"]
        try? kill.run()
        kill.waitUntilExit()
        super.tearDown()
    }

    // MARK: - Add

    @MainActor
    func testEmptyStateThenAddForwardShowsRow() {
        let ctx = UITestContext()
        let app = ctx.makeApp()
        app.launch()

        // Empty state visible.
        XCTAssertTrue(app.element(id: A11y.emptyState).waitForExistence(timeout: 5))

        // Open the editor from the toolbar and fill it in.
        app.buttons[A11y.addButton].click()
        let name = app.textFields[A11y.Editor.name]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeText("Demo Forward")

        // The default kind is Local, so the first port row shows listen + dest.
        let listenPort = app.textFields[A11y.Editor.listenPort(0)]
        listenPort.click()
        listenPort.typeText("5432")

        let remotePort = app.textFields[A11y.Editor.remotePort(0)]
        remotePort.click()
        remotePort.typeText("5432")

        app.buttons[A11y.Editor.save].click()

        // Row appears in the list.
        XCTAssertTrue(app.staticTexts["Demo Forward"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAddSecondPortMappingShowsRow() {
        let ctx = UITestContext()
        let app = ctx.makeApp()
        app.launch()

        app.buttons[A11y.addButton].click()
        let name = app.textFields[A11y.Editor.name]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeText("Devbox")

        // First mapping (the row that always exists).
        let listen0 = app.textFields[A11y.Editor.listenPort(0)]
        listen0.click()
        listen0.typeText("3000")
        let remote0 = app.textFields[A11y.Editor.remotePort(0)]
        remote0.click()
        remote0.typeText("3000")

        // Add a second mapping and fill it in via the indexed identifiers.
        app.buttons[A11y.Editor.addPort].click()
        let listen1 = app.textFields[A11y.Editor.listenPort(1)]
        XCTAssertTrue(listen1.waitForExistence(timeout: 3))
        listen1.click()
        listen1.typeText("8080")
        let remote1 = app.textFields[A11y.Editor.remotePort(1)]
        remote1.click()
        remote1.typeText("8080")

        app.buttons[A11y.Editor.save].click()

        // The connection saves (both mappings validated) and the row appears.
        XCTAssertTrue(app.staticTexts["Devbox"].waitForExistence(timeout: 5))
    }

    // MARK: - Validation

    @MainActor
    func testInvalidFormKeepsSheetOpenAndShowsError() {
        let ctx = UITestContext()
        let app = ctx.makeApp()
        app.launch()

        app.buttons[A11y.addButton].click()
        let save = app.buttons[A11y.Editor.save]
        XCTAssertTrue(save.waitForExistence(timeout: 5))

        // Save with an empty form -> inline error, sheet stays open.
        save.click()
        XCTAssertTrue(app.element(id: A11y.Editor.error).waitForExistence(timeout: 3))
        XCTAssertTrue(save.exists, "editor sheet should remain open after a validation error")
    }

    // MARK: - Toggle / connection state

    @MainActor
    func testTogglingForwardBringsItUp() {
        let ctx = UITestContext(seed: Seeds.oneDisabledLocal)
        let app = ctx.makeApp()
        app.launch()

        let toggle = app.element(id: A11y.toggle(Seeds.disabledLocalID))
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()

        // After the grace window the fake tunnel is reported as connected.
        let dot = app.element(id: A11y.statusDot(Seeds.disabledLocalID))
        let connected = expectation(for: NSPredicate(format: "label == %@", "Connected"),
                                    evaluatedWith: dot)
        wait(for: [connected], timeout: 8)
    }

    // MARK: - Persistence

    @MainActor
    func testAddedForwardPersistsAcrossRelaunch() {
        let ctx = UITestContext()
        let app = ctx.makeApp()
        app.launch()

        app.buttons[A11y.addButton].click()
        let name = app.textFields[A11y.Editor.name]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click(); name.typeText("Persisted One")
        let listenPort = app.textFields[A11y.Editor.listenPort(0)]
        listenPort.click(); listenPort.typeText("2200")
        let remotePort = app.textFields[A11y.Editor.remotePort(0)]
        remotePort.click(); remotePort.typeText("22")
        app.buttons[A11y.Editor.save].click()
        XCTAssertTrue(app.staticTexts["Persisted One"].waitForExistence(timeout: 5))

        // Relaunch against the same config dir (no seed) — it should still be there.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Persisted One"].waitForExistence(timeout: 5))
    }
}
