//
//  LoginSmokeTests.swift
//  FlipcashUITests
//

import XCTest

final class LoginSmokeTests: BaseUITestCase {
    override var requiresAuthentication: Bool { true }

    func testLoginViaAccessKey_reachesMainScreen() {
        assertMainScreenReached(
            "Expected to reach the main screen with the Give button after login"
        )

        let walletButton = app.buttons["Wallet"]
        XCTAssertTrue(
            walletButton.exists,
            "Expected to see the Wallet button on the main screen"
        )
    }

    func testRelogin_viaAccountSelection() {
        // Verify we're on the main screen
        assertMainScreenReached()

        // Open Settings and log out
        waitAndTap(app.buttons["Settings"])
        waitAndTap(app.buttons["Log Out"])

        // Confirmation dialog — scoped to the dialog container
        let dialog = app.otherElements["Are You Sure You Want To Log Out?"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 30), "Expected logout confirmation dialog")
        dialog.buttons["Log Out"].tap()

        // Should be back on IntroScreen
        let loginButton = app.buttons["Log In"]
        XCTAssertTrue(
            loginButton.waitForExistence(timeout: 30),
            "Expected to see IntroScreen after logout"
        )
        loginButton.tap()

        // Account Selection should show our previously logged-in account
        let selectAccountTitle = app.staticTexts["Select Account"]
        XCTAssertTrue(
            selectAccountTitle.waitForExistence(timeout: 30),
            "Expected to see Account Selection screen with saved accounts"
        )

        // Tap the first account in the list
        app.cells.firstMatch.tap()

        // Should reach main screen again
        assertMainScreenReached(
            "Expected to reach the main screen after re-login via account selection"
        )
    }
}
