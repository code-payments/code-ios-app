//
//  ConvertFromDollarsRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for converting Dollars into a currency the account already
/// holds — the tab-bar UI's route for what the v1 UI called Buy paying with
/// reserves. Asserts that:
///
/// - The Dollars card's info page offers Convert like any other holding.
/// - Converting *from* Dollars defaults the destination to the largest other
///   holding rather than to Dollars, so the flow reaches confirmation without
///   touching the picker.
/// - A covered amount routes straight to the swap: the Add Money picker must
///   never appear.
/// - After OK the user lands on the Wallet root, not back on the Dollars page.
///
/// Moves ~$0.01 of real dev-environment value per run.
///
/// **Prerequisites:**
/// - A valid `FLIPCASH_UI_TEST_ACCESS_KEY` set in `secrets.local.xcconfig`
/// - The test account must have non-zero USDF reserves
/// - The account must hold at least one non-USDF currency, as the convert
///   destination — Convert only offers balances the account already has
final class ConvertFromDollarsRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testConvert_dollarsToHeldToken_fullFlow() {
        let wallet = WalletScreen(app: app)
        let currencyInfo = CurrencyInfoUIScreen(app: app)
        let convert = ConvertFlowScreen(app: app)
        let amountEntry = AmountEntryScreen(app: app)
        let processing = SwapProcessingUIScreen(app: app)

        assertMainScreenReached()

        // Wallet tab → the Dollars card → its info page.
        wallet.open(from: self)
        wallet.selectUsdfCurrency()
        currencyInfo.assertHeldCurrencyReached()

        // Convert → $0.01 → Next. Dollars can't be its own destination, so the
        // amount screen opens on a token already.
        waitAndTap(currencyInfo.convertButton)
        convert.assertAmountStepReached()
        amountEntry.enterMinimumAmount()
        waitUntilHittableAndTap(amountEntry.nextButton)

        convert.assertConfirmationReached()
        waitUntilHittableAndTap(convert.confirmButton)

        // $0.01 is well inside any plausible USDF balance, so the flow must not
        // detour through Add Money.
        XCTAssertFalse(
            app.staticTexts["Add Money With"].waitForExistence(timeout: 2),
            "A covered amount must route straight to the swap, not the Add Money sheet"
        )

        processing.assertReached()
        processing.waitForCompletionAndDismiss()

        assertMainScreenReached("Expected the Wallet root after a completed convert")
    }
}
