//
//  BuyReservesRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the full buy flow using the user's USDF reserve as
/// the funding source. Asserts that:
///
/// - The buy nested sheet opens on top of CurrencyInfoScreen.
/// - A sub-cent entry the USDF balance can cover routes straight to the
///   swap-processing screen (no PurchaseMethodSheet appears).
/// - After OK on the processing screen, the user lands back on
///   CurrencyInfoScreen — not the Wallet root, not the Scanner.
///
/// **Prerequisites:**
/// - A valid `FLIPCASH_UI_TEST_ACCESS_KEY` set in `secrets.local.xcconfig`
/// - The test account must have non-zero USDF reserves
/// - The test account must have at least one non-USDF currency visible in
///   Wallet (the first row is used as the buy target)
final class BuyReservesRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testBuyCurrency_fullFlowWithReserves() {
        let wallet = WalletScreen(app: app)
        let currencyInfo = CurrencyInfoUIScreen(app: app)
        let amountEntry = AmountEntryScreen(app: app)
        let processing = SwapProcessingUIScreen(app: app)

        assertMainScreenReached()

        // Navigate: Main → Wallet → first currency → CurrencyInfoScreen
        wallet.open(from: self)
        wallet.selectFirstCurrency()
        currencyInfo.assertReached()

        // Buy → enter $0.01 → submit. The amount is well below any plausible
        // USDF balance, so the USDF gate routes straight to the swap.
        waitAndTap(currencyInfo.buyButton)
        amountEntry.enterMinimumAmount()
        waitUntilHittableAndTap(amountEntry.buyActionButton)

        // Wait for the swap to settle and dismiss via OK.
        processing.waitForCompletionAndDismiss()

        // OK on the processing screen pops the entire .buy nested sheet,
        // revealing CurrencyInfoScreen underneath. A regression here means
        // OK dismissed the wallet too (the cascading-dismiss bug fixed by
        // guarding the nested binding's setter against post-dismiss nil).
        currencyInfo.assertReached()
    }
}
