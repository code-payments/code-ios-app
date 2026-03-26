//
//  ApplicationLogsRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression tests for the Application Logs screen.
/// Verifies the user can navigate to the logs screen and share logs.
final class ApplicationLogsRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    // MARK: - Tests

    func testApplicationLogs_shareLogsPresentsShareSheet() {
        let settings = SettingsUIScreen(app: app)

        assertMainScreenReached()

        // Navigate: Main → Settings → Advanced Features → Application Logs
        settings.open(from: self)
        settings.navigateToAdvancedFeatures(from: self)
        waitAndTap(settings.applicationLogsRow)

        // Verify the Application Logs screen is displayed
        let title = app.navigationBars["Application Logs"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 10),
            "Expected Application Logs screen to appear"
        )

        // Verify the description text is visible
        let description = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Share a copy of recent app activity")
        ).firstMatch
        XCTAssertTrue(
            description.waitForExistence(timeout: 5),
            "Expected description text on the Application Logs screen"
        )

        // Tap "Share Logs" to trigger the export and share sheet
        waitAndTap(app.buttons["Share Logs"])

        // Share sheet actions are cells, not buttons. "Save to Files" only
        // appears when the sheet has a valid file attachment — proving the
        // log export succeeded and produced a real file.
        let saveToFiles = app.cells["Save to Files"]
        XCTAssertTrue(
            saveToFiles.waitForExistence(timeout: 15),
            "Expected share sheet to appear with Save to Files action"
        )

        // Dismiss the share sheet by swiping down
        app.swipeDown()

        // Verify we're back on the Application Logs screen
        XCTAssertTrue(
            title.waitForExistence(timeout: 5),
            "Expected to return to Application Logs screen after dismissing share sheet"
        )
    }
}
