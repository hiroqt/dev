import AppKit
import XCTest

@MainActor
final class WorkspaceFlowTests: XCTestCase {
    func testNotchExpansionAndFloatingTools() throws {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 24 }) else {
            throw XCTSkip("Requires a display with a physical notch")
        }
        let app = XCUIApplication()
        app.launchArguments += ["-quickSummaryEnabled", "YES"]
        app.launch()
        let expand = app.buttons["Open project summary"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        let notchWidth = (screen.auxiliaryTopRightArea?.minX ?? screen.frame.midX + 90)
            - (screen.auxiliaryTopLeftArea?.maxX ?? screen.frame.midX - 90)
        let idleWidth = min(notchWidth + 96, screen.frame.width - 24)
        XCTAssertLessThanOrEqual(expand.frame.width, idleWidth + 1)
        expand.click()
        let minimize = app.buttons["Minimize summary to notch"]
        XCTAssertTrue(minimize.waitForExistence(timeout: 5))
        for tool in ["workspace", "skills", "terminal", "codex"] {
            XCTAssertTrue(app.buttons["notch-widget-\(tool)"].exists)
        }
        app.buttons["notch-widget-terminal"].click()
        let terminal = app.descendants(matching: .any)["notch-terminal"]
        XCTAssertTrue(terminal.waitForExistence(timeout: 5))
        app.buttons["notch-widget-skills"].click()
        XCTAssertTrue(app.textFields["notch-skills-search"].waitForExistence(timeout: 3))
        app.buttons["notch-widget-workspace"].click()
        XCTAssertTrue(app.buttons["Open Workspace"].exists)
        minimize.click()
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(expand.frame.width, idleWidth + 1)
        expand.click()
        app.buttons["notch-widget-terminal"].click()
        XCTAssertTrue(terminal.waitForExistence(timeout: 3))
        minimize.click()
    }

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
        XCTAssertTrue(app.staticTexts["Local Projects"].exists)
        XCTAssertTrue(app.buttons["add-local-project"].exists)

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

    func testSidebarOpensSkillsLibraryInExpandedAndCompactModes() throws {
        let app = XCUIApplication()
        app.launch()

        let skills = app.descendants(matching: .any)["nav-skills"]
        XCTAssertTrue(skills.waitForExistence(timeout: 5))
        skills.click()
        XCTAssertTrue(app.textFields["skills-search"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["skills-add-folder"].exists)

        app.buttons["sidebar-toggle"].click()
        let compactSkills = app.buttons["compact-nav-skills"]
        XCTAssertTrue(compactSkills.waitForExistence(timeout: 3))
        compactSkills.click()
        XCTAssertTrue(app.textFields["skills-search"].waitForExistence(timeout: 3))
    }
}
