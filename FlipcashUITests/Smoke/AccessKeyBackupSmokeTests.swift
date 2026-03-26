//
//  AccessKeyBackupSmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// Smoke tests for viewing and interacting with the Access Key from Settings.
final class AccessKeyBackupSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }
    override var resetPermissions: [XCUIProtectedResource] { [.photos] }

    // MARK: - Tests

    func testAccessKeyBackup_viewFromSettings() {
        let settings = SettingsUIScreen(app: app)

        assertMainScreenReached()

        // Navigate: Main → Settings → My Account → Access Key
        settings.open(from: self)
        settings.navigateToMyAccount(from: self)
        waitAndTap(settings.accessKeyRow)

        // Confirmation dialog: "View Your Access Key?"
        let dialog = app.otherElements["View Your Access Key?"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 10), "Expected access key confirmation dialog")
        dialog.buttons["View Access Key"].tap()

        // AccessKeyBackupScreen should appear with the "Save to Photos" button
        let saveButton = app.buttons["Save to Photos"]
        XCTAssertTrue(
            saveButton.waitForExistence(timeout: 10),
            "Expected AccessKeyBackupScreen with 'Save to Photos' button"
        )
    }

    func testAccessKeyBackup_copyToClipboard() {
        let settings = SettingsUIScreen(app: app)

        assertMainScreenReached()

        // Navigate to the Access Key screen
        settings.open(from: self)
        settings.navigateToMyAccount(from: self)
        waitAndTap(settings.accessKeyRow)

        let dialog = app.otherElements["View Your Access Key?"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 10), "Expected access key confirmation dialog")
        dialog.buttons["View Access Key"].tap()

        // Wait for the access key card to appear
        let saveButton = app.buttons["Save to Photos"]
        XCTAssertTrue(
            saveButton.waitForExistence(timeout: 10),
            "Expected AccessKeyBackupScreen to load"
        )

        // Long-press the access key card to trigger the context menu.
        // The `.contextMenu` modifier is on the AccessKey view which sits in the
        // center of the screen. Use a normalized coordinate to press there reliably,
        // avoiding fragile element queries on the card's internal image/text children.
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        center.press(forDuration: 1.5)

        // Context menus animate in — wait for hittable to avoid tapping during animation.
        let copyButton = app.buttons["Copy"]
        waitUntilHittableAndTap(copyButton, timeout: 5, "Expected 'Copy' option in context menu")
    }

    func testAccessKeyBackup_saveToPhotos() {
        let settings = SettingsUIScreen(app: app)

        assertMainScreenReached()

        // Navigate to the Access Key screen
        settings.open(from: self)
        settings.navigateToMyAccount(from: self)
        waitAndTap(settings.accessKeyRow)

        let dialog = app.otherElements["View Your Access Key?"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 10), "Expected access key confirmation dialog")
        dialog.buttons["View Access Key"].tap()

        // Tap "Save to Photos"
        waitAndTap(app.buttons["Save to Photos"])

        // Allow Photos access via the system permission dialog
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        waitUntilHittableAndTap(springboard.buttons["Allow"])

        // The button should transition to success state (checkmark).
        // We verify the button is no longer showing the original title,
        // indicating it transitioned to .success state.
        let saveButton = app.buttons["Save to Photos"]
        let disappeared = saveButton.waitForNonExistence(timeout: 10)
        XCTAssertTrue(
            disappeared,
            "Expected 'Save to Photos' button to transition to success state"
        )
    }
}
