//
//  CurrencySellRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the full currency sell flow with confirmation.
///
/// **Prerequisites:**
/// - A valid `FLIPCASH_UI_TEST_ACCESS_KEY` set in `secrets.local.xcconfig`
/// - The test account must hold at least one non-USDF currency with balance > 0
final class CurrencySellRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testSellCurrency_fullFlowWithConfirmation() {
        let wallet = WalletScreen(app: app)
        let currencyInfo = CurrencyInfoUIScreen(app: app)
        let amountEntry = AmountEntryScreen(app: app)
        let confirmation = SellConfirmationScreen(app: app)
        let processing = SwapProcessingUIScreen(app: app)

        assertMainScreenReached()

        // Navigate: Main → Wallet → first currency → CurrencyInfoScreen
        wallet.open(from: self)
        wallet.selectFirstCurrency()
        currencyInfo.assertReached()

        // Sell → enter $0.01 → Next → confirm → submit
        waitAndTap(currencyInfo.sellButton, timeout: 10, "Expected Sell button — test account must hold this currency")
        amountEntry.enterMinimumAmount()
        waitAndTap(amountEntry.nextButton)
        confirmation.confirmSell(from: self)

        // Wait for swap to complete and dismiss
        processing.waitForCompletionAndDismiss()

        // Verify we returned to CurrencyInfoScreen
        currencyInfo.assertReached()
    }
}
