//
//  CreateAccountSmokeTests.swift
//  FlipcashUITests
//

import XCTest

final class CreateAccountSmokeTests: BaseUITestCase {

    override var resetPermissions: [XCUIProtectedResource] { [.photos] }

    // MARK: - Tests

    func testCreateAccount_saveToPhotos() {
        waitAndTap(app.buttons["Create a New Account"])

        // AccessKeyScreen
        waitAndTap(app.buttons["Save Access Key to Photos"])

        // System "add to Photos" permission alert (belongs to Springboard).
        // Use waitUntilHittableAndTap because the dialog animates in and
        // tapping during the animation can miss the button.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        waitUntilHittableAndTap(springboard.buttons["Allow"])

        // Push notification permission screen (may be skipped if already granted)
        allowPushNotificationsIfNeeded()

        assertMainScreenReached(
            "Expected to reach the main screen after account creation via Save to Photos"
        )
    }

    func testCreateAccount_wroteDownInstead() {
        waitAndTap(app.buttons["Create a New Account"])

        // AccessKeyScreen
        waitAndTap(app.buttons["Wrote the 12 Words Down Instead?"])

        // Confirmation dialog: "Are You Sure?"
        waitAndTap(app.buttons["Yes, I Wrote Them Down"])

        // Push notification permission screen (may be skipped if already granted)
        allowPushNotificationsIfNeeded()

        assertMainScreenReached(
            "Expected to reach the main screen after account creation via Wrote Down"
        )
    }
}
