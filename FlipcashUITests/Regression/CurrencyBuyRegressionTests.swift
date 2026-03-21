//
//  CurrencyBuyRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the full currency buy flow using USDF reserves.
///
/// **Prerequisites:**
/// - A valid `FLIPCASH_UI_TEST_ACCESS_KEY` set in `secrets.local.xcconfig`
/// - The test account must have USDF reserves
/// - The test account must have at least one non-USDF currency visible in Wallet
final class CurrencyBuyRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testBuyCurrency_fullFlowWithReserves() {
        let wallet = WalletScreen(app: app)
        let currencyInfo = CurrencyInfoUIScreen(app: app)
        let funding = FundingSelectionScreen(app: app)
        let amountEntry = AmountEntryScreen(app: app)
        let processing = SwapProcessingUIScreen(app: app)

        assertMainScreenReached()

        // Navigate: Main → Wallet → first currency → CurrencyInfoScreen
        wallet.open(from: self)
        wallet.selectFirstCurrency()
        currencyInfo.assertReached()

        // Buy → select USDF reserves → enter $0.01 → submit
        waitAndTap(currencyInfo.buyButton)
        funding.selectUSDF(from: self)
        amountEntry.enterMinimumAmount()
        waitUntilHittableAndTap(amountEntry.buyActionButton)

        // Wait for swap to complete and dismiss
        processing.waitForCompletionAndDismiss()

        // Verify we returned to CurrencyInfoScreen
        currencyInfo.assertReached()
    }
}
