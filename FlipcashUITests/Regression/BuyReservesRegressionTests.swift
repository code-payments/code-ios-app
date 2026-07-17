//
//  BuyReservesRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the full buy flow paying with USDF. Asserts that:
///
/// - The buy nested sheet opens on top of CurrencyInfoScreen.
/// - Next pushes the Select Payment Currency step; picking USDF lands on the
///   Buy summary in its simple (no fee breakdown) variant.
/// - A covered entry routes straight to the swap-processing screen (the Add
///   Money "Select Method" sheet never appears).
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
        let paymentCurrency = PaymentCurrencyUIScreen(app: app)
        let confirmation = BuyConfirmationUIScreen(app: app)
        let processing = SwapProcessingUIScreen(app: app)

        assertMainScreenReached()

        // Navigate: Main → Wallet → first currency → CurrencyInfoScreen
        wallet.open(from: self)
        wallet.selectFirstCurrency()
        currencyInfo.assertReached()

        // Buy → enter $0.01 → Next → USDF → summary → Buy. The amount is well
        // below any plausible USDF balance, so USDF is always eligible.
        waitAndTap(currencyInfo.buyButton)
        amountEntry.enterMinimumAmount()
        waitUntilHittableAndTap(amountEntry.nextButton)

        paymentCurrency.assertReached()
        waitAndTap(paymentCurrency.usdfRow)

        confirmation.assertReached()
        // The USDF variant is the simple summary — no fee breakdown.
        XCTAssertFalse(
            confirmation.exchangeFeeRow.exists,
            "USDF-paid buys must not show an Exchange fee row"
        )
        waitUntilHittableAndTap(confirmation.buyButton)

        // A covered amount must not detour through the Add Money flow — the
        // "Select Method" sheet must never appear.
        XCTAssertFalse(
            app.staticTexts["Select Method"].waitForExistence(timeout: 2),
            "A covered amount must route straight to the swap, not the Add Money sheet"
        )

        processing.assertReached()

        // Swipe-down on the processing screen must NOT dismiss the .buy sheet.
        // Two known regressions break this:
        //   1) The recursive `.appRouterNestedSheet(...)` call inside the
        //      depth-1 sheet content swallows `interactiveDismissDisabled`
        //      preferences from descendants.
        //   2) A source-level `.interactiveDismissDisabled(false)` on
        //      BuyAmountScreen overrides the destination's `true`.
        // After the swipe, the processing title must still be visible.
        app.swipeDown()
        processing.assertReached(timeout: 5)

        // Wait for the swap to settle and dismiss via OK.
        processing.waitForCompletionAndDismiss()

        // OK on the processing screen pops the entire .buy nested sheet,
        // revealing CurrencyInfoScreen underneath. A regression here means
        // OK dismissed the wallet too (the cascading-dismiss bug fixed by
        // guarding the nested binding's setter against post-dismiss nil).
        currencyInfo.assertReached()
    }
}
