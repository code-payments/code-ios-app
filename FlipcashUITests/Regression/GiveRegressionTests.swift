//
//  GiveRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression: tapping Give on an account with no giveable balance must
/// surface the "No Balance Yet" dialog *without* presenting the give amount
/// entry sheet behind it. Previously the sheet was presented unconditionally
/// alongside the dialog, leaving the user staring at a $0 keypad once the
/// dialog was dismissed.
///
/// Uses fresh-account creation to guarantee a $0 balance — no auth keys
/// required, runs the same on Xcode Cloud as locally.
final class GiveRegressionTests: BaseUITestCase {

    func testGiveWithNoBalance_showsDialogWithoutPresentingAmountEntry() {
        // Walk the fastest fresh-account path: write-down branch, no Photos
        // permission needed.
        waitAndTap(app.buttons["Create a New Account"])
        waitAndTap(app.buttons["Wrote the 12 Words Down Instead?"])
        waitAndTap(app.buttons["Yes, I Wrote Them Down"])
        allowPushNotificationsIfNeeded()
        assertMainScreenReached()

        waitAndTap(app.buttons["Give"])

        // The dialog hosts at `UIWindow.Level.alert`; XCUITest still reaches
        // it through the same `app` query because both windows belong to the
        // app's process.
        let noBalanceTitle = app.staticTexts["No Balance Yet"]
        XCTAssertTrue(
            noBalanceTitle.waitForExistence(timeout: 10),
            "Expected 'No Balance Yet' dialog after tapping Give on an empty account"
        )

        // The give amount entry's "Next" action button is the cleanest proxy
        // for "the amount entry sheet is in the hierarchy". If it exists
        // while the dialog is up, the sheet has been presented behind it —
        // the regression.
        XCTAssertFalse(
            app.buttons["Next"].exists,
            "Give amount entry must not present when the balance check fails — 'Next' button found alongside dialog"
        )

        waitAndTap(app.buttons["OK"])

        // Dismissing the dialog must land the user on the main screen, not
        // reveal a $0 amount entry that was hiding underneath.
        XCTAssertFalse(
            app.buttons["Next"].waitForExistence(timeout: 3),
            "Dismissing 'No Balance Yet' revealed a hidden Give amount entry — sheet was presented behind the dialog"
        )
        assertMainScreenReached(timeout: 5, "Expected to return to the main screen after dismissing the No Balance dialog")
    }
}
