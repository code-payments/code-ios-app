//
//  GiveRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression: tapping Cash on an account with no giveable balance must
/// surface the standard "No Balance Yet" `Dialog` *without* presenting the give
/// amount entry sheet behind it. Previously the give sheet was presented
/// unconditionally, leaving the user staring at a $0 keypad once the prompt was
/// dismissed. The dialog's "Add Money" action opens the deposit method picker
/// (`.addMoney`); "Cancel" returns to the main screen.
///
/// Uses fresh-account creation to guarantee a $0 balance — no auth keys
/// required, runs the same on Xcode Cloud as locally.
final class GiveRegressionTests: BaseUITestCase {

    func testGiveWithNoBalance_showsAddMoneyWithoutPresentingAmountEntry() {
        // Walk the fastest fresh-account path: write-down branch, no Photos
        // permission needed.
        waitAndTap(app.buttons["Create a New Account"])
        waitAndTap(app.buttons["Wrote the 12 Words Down Instead?"])
        waitAndTap(app.buttons["Yes, I Wrote Them Down"])
        allowPhoneVerificationIfNeeded()
        allowPushNotificationsIfNeeded()
        assertMainScreenReached()

        waitAndTap(app.buttons["Cash"])

        let noBalanceTitle = app.staticTexts["No Balance Yet"]
        XCTAssertTrue(
            noBalanceTitle.waitForExistence(timeout: 10),
            "Expected the 'No Balance Yet' Add Money prompt after tapping Cash on an empty account"
        )

        // The Add Money prompt's primary CTA — confirms we routed to the Add
        // Money flow, not the give amount entry or the legacy deposit dialog.
        XCTAssertTrue(
            app.buttons["Add Money"].exists,
            "Expected the 'Add Money' CTA on the No Balance prompt"
        )

        // "Next" stands in for the give amount-entry sheet being in the hierarchy.
        XCTAssertFalse(
            app.buttons["Next"].exists,
            "Give amount entry must not present when the balance check fails — 'Next' button found alongside the prompt"
        )

        waitAndTap(app.buttons["Cancel"])

        assertMainScreenReached(timeout: 5, "Expected to return to the main screen after dismissing the No Balance prompt")
        XCTAssertFalse(
            app.buttons["Next"].exists,
            "Dismissing 'No Balance Yet' revealed a hidden Give amount entry — sheet was presented behind the dialog"
        )
    }
}
