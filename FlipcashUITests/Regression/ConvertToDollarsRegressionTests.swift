//
//  ConvertToDollarsRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for converting a held token into Dollars — the tab-bar UI's
/// route for what the v1 UI called Sell. Asserts that:
///
/// - A held currency's info page offers Convert, and Convert pushes the amount
///   screen onto the same stack rather than presenting a sheet.
/// - A non-Dollars source defaults its destination to Dollars, so the flow
///   reaches confirmation without touching the picker.
/// - After OK on the processing screen the user lands on the Wallet root:
///   `ConvertFlowDestinationView` pops the convert stack and dismisses the
///   token-info card overlay it launched from, so the currency page does not
///   come back.
///
/// Moves ~$0.01 of real dev-environment value per run.
///
/// **Prerequisites:**
/// - A valid `FLIPCASH_UI_TEST_ACCESS_KEY` set in `secrets.local.xcconfig`
/// - The test account must hold at least one non-USDF currency with balance > 0
final class ConvertToDollarsRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testConvert_heldTokenToDollars_fullFlow() {
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

        // Convert → $0.01 → Next. The destination is already Dollars.
        waitAndTap(currencyInfo.convertButton)
        convert.assertAmountStepReached()
        amountEntry.enterMinimumAmount()
        waitUntilHittableAndTap(amountEntry.nextButton)

        convert.assertConfirmationReached()
        waitUntilHittableAndTap(convert.confirmButton)

        processing.assertReached()
        processing.waitForCompletionAndDismiss()

        assertMainScreenReached("Expected the Wallet root after a completed convert")
    }
}
