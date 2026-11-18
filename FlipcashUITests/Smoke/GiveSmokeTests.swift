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

        // Wallet → first currency card → Send tile → keypad.
        let amountEntry = navigateToGiveAmount()

        // Enter $0.01, then give it as cash from Select Recipient
        amountEntry.enterMinimumAmount()
        waitAndTap(amountEntry.nextButton)
        tapGiveAsCash()

        // Bill should appear with "Send as a Link" button
        let sendAsLink = app.buttons["Send as a Link"]
        XCTAssertTrue(
            sendAsLink.waitForExistence(timeout: 30),
            "Expected the bill to appear with the 'Send as a Link' button"
        )

        // Dismiss the bill
        waitAndTap(app.buttons["Cancel"])

        // Cancelling reveals Select Recipient; back out to the currency's info
        // screen. The tab bar stays hidden while the wallet stack is pushed, so
        // `assertMainScreenReached` would not hold here.
        backOutOfGiveToCurrencyInfo()
        currencyInfo.assertHeldCurrencyReached(
            timeout: 30
        )
    }
}
