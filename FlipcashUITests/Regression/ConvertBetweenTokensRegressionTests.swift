//
//  ConvertBetweenTokensRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for converting one held token into another — the tab-bar
/// UI's route for what the v1 UI called buying with a currency. This is the
/// only convert direction that has to open the destination picker: a
/// non-Dollars source defaults to Dollars, so reaching another token means
/// choosing it.
///
/// Asserts that the picker lists a token other than the source (it filters the
/// source out), and that the chosen destination carries through amount entry to
/// confirmation and the swap.
///
/// Moves ~$0.01 of real dev-environment value per run.
///
/// **Prerequisites:**
/// - A valid `FLIPCASH_UI_TEST_ACCESS_KEY` set in `secrets.local.xcconfig`
/// - The account holds at least TWO non-USDF currencies, the source with a
///   balance > 0
final class ConvertBetweenTokensRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testConvert_tokenToToken_fullFlow() {
        let wallet = WalletScreen(app: app)
        let currencyInfo = CurrencyInfoUIScreen(app: app)
        let convert = ConvertFlowScreen(app: app)
        let amountEntry = AmountEntryScreen(app: app)
        let processing = SwapProcessingUIScreen(app: app)

        assertMainScreenReached()

        // Wallet tab → first non-USDF card → its info page.
        wallet.open(from: self)
        wallet.selectFirstCurrency()
        currencyInfo.assertHeldCurrencyReached()

        waitAndTap(currencyInfo.convertButton)
        convert.assertAmountStepReached()

        // Override the Dollars default with a token. The source is filtered out
        // of the options, so the first non-Dollars row is always a different
        // currency.
        waitUntilHittableAndTap(convert.destinationButton)
        XCTAssertTrue(
            convert.pickerTitle.waitForExistence(timeout: 10),
            "Expected the Select Currency sheet"
        )
        XCTAssertTrue(
            convert.pickerFirstTokenRow.waitForExistence(timeout: 10),
            "Fixture requires a second non-USDF currency to convert into"
        )
        waitUntilHittableAndTap(convert.pickerFirstTokenRow)

        amountEntry.enterMinimumAmount()
        waitUntilHittableAndTap(amountEntry.nextButton)

        convert.assertConfirmationReached()
        waitUntilHittableAndTap(convert.confirmButton)

        processing.assertReached()
        processing.waitForCompletionAndDismiss()

        assertMainScreenReached("Expected the Wallet root after a completed convert")
    }
}
