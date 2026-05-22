//
//  BuyDepositRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the Deposit USDC funding path from the buy picker.
/// Exercises the in-app flow end-to-end:
///
/// - The buy nested sheet opens on top of CurrencyInfoScreen.
/// - An amount above the USDF balance routes to `PurchaseMethodSheet`.
/// - Selecting "Deposit USDC" dismisses the buy nested sheet and pushes
///   `USDCDepositEducationScreen` onto the balance stack (on top of the
///   CurrencyInfo destination underneath).
/// - Tapping Next pushes `USDCDepositAddressScreen` with the Copy Address
///   button hittable. The address itself is derived from the session's
///   owner key — its exact value isn't asserted, just that the CTA renders.
///
/// **Prerequisites:**
/// - A valid `FLIPCASH_UI_TEST_ACCESS_KEY` set in `secrets.local.xcconfig`
/// - The test account must have at least one non-USDF currency visible in
///   Wallet (the first row is used as the buy target).
final class BuyDepositRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testDepositFlow_depositUSDC_pushesOntoBalanceStack() {
        let wallet = WalletScreen(app: app)
        let currencyInfo = CurrencyInfoUIScreen(app: app)
        let amountEntry = AmountEntryScreen(app: app)
        let purchaseMethods = PurchaseMethodSheet(app: app)
        let depositEducation = USDCDepositEducationScreen(app: app)
        let depositAddress = USDCDepositAddressScreen(app: app)

        assertMainScreenReached()

        // Navigate: Main → Wallet → first currency → CurrencyInfoScreen → Buy
        wallet.open(from: self)
        wallet.selectFirstCurrency()
        currencyInfo.assertReached()
        waitAndTap(currencyInfo.buyButton)

        // Enter a high amount so the USDF gate fails and the picker shows.
        amountEntry.enterPickerTriggeringAmount()
        waitUntilHittableAndTap(amountEntry.buyActionButton)

        // Picker → Deposit USDC → buy sheet dismisses, education pushes.
        purchaseMethods.assertReached()
        purchaseMethods.selectDepositUSDC(from: self)

        depositEducation.assertReached()

        // The buy "Amount" screen must dismiss as part of the hand-off — the
        // education screen lives on the balance stack now, not inside the
        // buy nested sheet.
        XCTAssertTrue(
            app.navigationBars["Amount"].waitForNonExistence(timeout: 2),
            "Buy Amount screen must be dismissed before the education screen pushes"
        )

        depositEducation.tapNext(from: self)

        // Address screen renders with the Copy Address CTA. The address
        // value depends on the per-user PDA derivation and is not asserted.
        depositAddress.assertReached()
        XCTAssertTrue(
            depositAddress.copyAddressButton.isHittable,
            "Expected the Copy Address CTA to be hittable"
        )
    }
}
