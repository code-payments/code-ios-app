//
//  GiveSmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// Smoke: a give started from a held currency's Give tile reaches the bill, and
/// cancelling the bill returns to the currency it was started from.
final class GiveSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testGiveFlow_showsBillWithSendAsLink() {
        let currencyInfo = CurrencyInfoUIScreen(app: app)

        assertMainScreenReached()

        // Wallet → first currency card → Give tile → keypad.
        let amountEntry = navigateToGiveAmount()

        // Enter $0.01 and proceed to bill
        amountEntry.enterMinimumAmount()
        waitAndTap(amountEntry.nextButton)

        // Bill should appear with "Send as a Link" button
        let sendAsLink = app.buttons["Send as a Link"]
        XCTAssertTrue(
            sendAsLink.waitForExistence(timeout: 30),
            "Expected the bill to appear with the 'Send as a Link' button"
        )

        // Dismiss the bill
        waitAndTap(app.buttons["Cancel"])

        // The keypad popped itself as the bill appeared, so the bill sits over
        // the currency's info screen — that, not a tab root, is what cancelling
        // reveals. The tab bar stays hidden while the wallet stack is pushed, so
        // `assertMainScreenReached` would not hold here.
        currencyInfo.assertHeldCurrencyReached(
            timeout: 30
        )
    }
}
