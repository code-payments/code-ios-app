//
//  BuyWithCurrencyRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for buying a currency paying with another launchpad
/// currency: the multi-step flow (amount → Select Payment Currency → summary
/// with fee breakdown → processing) with a real $0.01 swap. The insufficient
/// sheet and the fee-affordable entry correction are covered deterministically
/// by `BuyConfirmationViewModelTests` and `BuyAmountViewModelTests` — a UI
/// rendition proved too balance-dependent to keep stable.
///
/// **Prerequisites:**
/// - A valid `FLIPCASH_UI_TEST_ACCESS_KEY` set in `secrets.local.xcconfig`
/// - The account holds USDF and at least TWO launchpad currencies
final class BuyWithCurrencyRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    /// Buys $0.01 of the first wallet currency paying with another launchpad
    /// token, all the way through the processing screen. Moves ~$0.01 of real
    /// dev-environment value per run.
    func testBuyCurrency_payingWithToken_fullFlow() throws {
        try skipPendingTabBarRewrite(
            "an owned currency's info page offers Give/Convert/Withdraw in the tab-bar UI — there is no Buy, and the buy flow pushes instead of opening a nested sheet"
        )

        let wallet = WalletScreen(app: app)
        let currencyInfo = CurrencyInfoUIScreen(app: app)
        let amountEntry = AmountEntryScreen(app: app)
        let paymentCurrency = PaymentCurrencyUIScreen(app: app)
        let confirmation = BuyConfirmationUIScreen(app: app)
        let processing = SwapProcessingUIScreen(app: app)

        assertMainScreenReached()

        // Target = first wallet currency; payment = first eligible token row
        // on the selector (the target's own row renders disabled and carries a
        // different identifier, so it can never be matched).
        wallet.open(from: self)
        wallet.selectFirstCurrency()
        currencyInfo.assertReached()

        waitAndTap(currencyInfo.buyButton)
        amountEntry.enterMinimumAmount()
        waitUntilHittableAndTap(amountEntry.nextButton)

        paymentCurrency.assertReached()
        XCTAssertTrue(
            paymentCurrency.firstTokenRow.waitForExistence(timeout: 10),
            "Fixture requires a second launchpad currency with a spendable balance"
        )
        waitAndTap(paymentCurrency.firstTokenRow)

        confirmation.assertReached()
        XCTAssertTrue(
            confirmation.exchangeFeeRow.waitForExistence(timeout: 5),
            "Token-paid buys must show the Exchange fee breakdown"
        )
        waitUntilHittableAndTap(confirmation.buyButton)

        processing.assertReached()
        processing.waitForCompletionAndDismiss()
        currencyInfo.assertReached()
    }
}
