//
//  CreateAccountSmokeTests.swift
//  FlipcashUITests
//

import XCTest

final class CreateAccountSmokeTests: BaseUITestCase {

    override var resetPermissions: [XCUIProtectedResource] { [.photos] }

    func testCreateAccount_saveToPhotos() {
        waitAndTap(app.buttons["Create a New Account"], timeout: 10)

        // AccessKeyScreen
        waitAndTap(app.buttons["Save Access Key to Photos"])

        // System "add to Photos" permission alert (belongs to Springboard)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow"]
        if allowButton.waitForExistence(timeout: 5) {
            allowButton.tap()
        }

        assertMainScreenReached(
            "Expected to reach the main screen after account creation via Save to Photos"
        )
    }

    func testCreateAccount_wroteDownInstead() {
        waitAndTap(app.buttons["Create a New Account"], timeout: 10)

        // AccessKeyScreen
        waitAndTap(app.buttons["Wrote the 12 Words Down Instead?"])

        // Confirmation dialog: "Are You Sure?"
        waitAndTap(app.buttons["Yes, I Wrote Them Down"])

        assertMainScreenReached(
            "Expected to reach the main screen after account creation via Wrote Down"
        )
    }
}
