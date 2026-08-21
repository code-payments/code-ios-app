//
//  CurrencyConvertRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the full currency convert flow with confirmation.
/// Converting a held currency to Dollars is what the old standalone Sell flow
/// became when the tab-bar UI shipped.
///
/// **Prerequisites:**
/// - A valid `FLIPCASH_UI_TEST_ACCESS_KEY` set in `secrets.local.xcconfig`
/// - The test account must hold at least one non-USDF currency with balance > 0
final class CurrencyConvertRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testConvertCurrency_fullFlowWithConfirmation() throws {
        try skipPendingTabBarRewrite("Convert replaced Sell and pushes onto the Wallet tab instead of presenting a sheet")

        let wallet = WalletScreen(app: app)
        let currencyInfo = CurrencyInfoUIScreen(app: app)
        let amountEntry = AmountEntryScreen(app: app)
        let confirmation = ConvertConfirmationUIScreen(app: app)
        let processing = SwapProcessingUIScreen(app: app)

        assertMainScreenReached()

        // Navigate: Main → Wallet → first currency → CurrencyInfoScreen
        wallet.open(from: self)
        wallet.selectFirstCurrency()
        currencyInfo.assertReached()

        // Convert → enter $0.01 → Next → confirm → submit
        waitAndTap(currencyInfo.convertButton, timeout: 10, "Expected Convert tile — test account must hold this currency")
        amountEntry.enterMinimumAmount()
        waitAndTap(amountEntry.nextButton)
        confirmation.confirmConvert(from: self)

        // Wait for swap to complete and dismiss
        processing.waitForCompletionAndDismiss()

        // Verify we returned to CurrencyInfoScreen
        currencyInfo.assertReached()
    }
}
