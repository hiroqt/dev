import XCTest

@MainActor
final class WorkspaceFlowTests: XCTestCase {
    func testUnconfiguredAppShowsNoPlaceholderRepositories() throws {
        let app = XCUIApplication()
        app.launch()

        let signIn = app.buttons["github-sign-in"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        XCTAssertEqual(signIn.label, "Sign in with GitHub")
        let destinationHeader = app.otherElements["workspace-header-title"]
        XCTAssertTrue(destinationHeader.waitForExistence(timeout: 3))
        XCTAssertEqual(destinationHeader.label, "All Projects")
        XCTAssertGreaterThanOrEqual(destinationHeader.frame.minX, app.buttons["sidebar-search"].frame.maxX)
        XCTAssertFalse(app.buttons["Refresh"].exists)
        XCTAssertFalse(app.textFields["Find a repository"].exists)

        app.buttons["sidebar-search"].click()
        let searchField = app.textFields["repository-search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.typeText("octo")
        XCTAssertTrue(app.staticTexts["No repositories yet"].exists)
        app.buttons["Done"].click()

        signIn.click()
        XCTAssertTrue(app.staticTexts["github-configuration-help"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["repository-1"].exists)
        XCTAssertFalse(app.buttons["project-momo"].exists)
    }

    func testSidebarOpensActivityAndSettings() throws {
        let app = XCUIApplication()
        app.launch()

        let sidebarToggle = app.descendants(matching: .any)["sidebar-toggle"]
        XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 3))
        XCTAssertEqual(sidebarToggle.label, "Hide Sidebar")
        let activity = app.descendants(matching: .any)["nav-activity"]
        XCTAssertTrue(activity.waitForExistence(timeout: 3))

        sidebarToggle.click()
        XCTAssertEqual(sidebarToggle.label, "Show Sidebar")
        XCTAssertFalse(activity.exists)
        XCTAssertTrue(app.buttons["compact-sidebar-search"].exists)
        let compactActivity = app.buttons["compact-nav-activity"]
        XCTAssertTrue(compactActivity.waitForExistence(timeout: 3))
        compactActivity.click()
        XCTAssertEqual(app.otherElements["workspace-header-title"].label, "Activity")
        sidebarToggle.click()
        XCTAssertTrue(activity.waitForExistence(timeout: 3))

        activity.click()
        XCTAssertEqual(app.otherElements["workspace-header-title"].label, "Activity")
        let yearSelector = app.descendants(matching: .any)["activity-year-selector"]
        XCTAssertTrue(yearSelector.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Refresh contribution activity"].exists)
        yearSelector.click()
        let priorYear = app.menuItems["2025"]
        XCTAssertTrue(priorYear.waitForExistence(timeout: 3))
        priorYear.click()
        app.descendants(matching: .any)["nav-settings"].click()
        XCTAssertEqual(app.otherElements["workspace-header-title"].label, "Settings")
    }
}
