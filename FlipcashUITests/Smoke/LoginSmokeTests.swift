//
//  LoginSmokeTests.swift
//  FlipcashUITests
//

import XCTest

final class LoginSmokeTests: BaseUITestCase {
    override var requiresAuthentication: Bool { true }

    func testLoginViaAccessKey_reachesMainScreen() {
        // The main screen (ScanScreen) should show the Give and Wallet buttons
        let giveButton = app.buttons["Give"]
        XCTAssertTrue(
            giveButton.waitForExistence(timeout: 15),
            "Expected to reach the main screen with the Give button after login"
        )

        let walletButton = app.buttons["Wallet"]
        XCTAssertTrue(
            walletButton.exists,
            "Expected to see the Wallet button on the main screen"
        )
    }
}
