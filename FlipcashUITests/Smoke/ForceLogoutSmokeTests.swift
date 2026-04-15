//
//  ForceLogoutSmokeTests.swift
//  FlipcashUITests
//

import XCTest

final class ForceLogoutSmokeTests: BaseUITestCase {

    /// An Access Key whose primary account has left the `locked` state.
    /// Logging in with it must land the user on ``ForceLogoutScreen`` and
    /// block access to the main UI. Safe to distribute — the account is
    /// already unusable server-side.
    private static let poisonedMnemonic =
        "discover gravity refuse faith sick chair dumb magnet mountain repair service ocean"

    func testLogin_withPoisonedAccount_showsForceLogoutScreen() {
        // IntroScreen
        waitAndTap(app.buttons["Log In"])

        // If the simulator remembers a prior account, switch to manual entry
        let enterDifferentKey = app.buttons["Enter a Different Access Key"]
        if enterDifferentKey.waitForExistence(timeout: 5) {
            enterDifferentKey.tap()
        }

        // LoginScreen — type the poisoned mnemonic
        let textEditor = app.textViews.firstMatch
        XCTAssertTrue(
            textEditor.waitForExistence(timeout: 30),
            "Expected to find the mnemonic text input"
        )
        textEditor.tap()
        textEditor.typeText(Self.poisonedMnemonic)

        // Submit
        waitAndTap(app.buttons["Log In"])

        // ForceLogoutScreen must appear
        let forceLogoutTitle = app.staticTexts["Access Key No Longer Usable in Flipcash"]
        XCTAssertTrue(
            forceLogoutTitle.waitForExistence(timeout: 30),
            "Expected ForceLogoutScreen when logging in with an unlocked access key"
        )

        // Main screen must NOT be reachable
        XCTAssertFalse(
            app.buttons["Give"].exists,
            "Main screen must not be reachable with an unlocked access key"
        )
    }
}
