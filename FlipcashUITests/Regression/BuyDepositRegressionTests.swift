//
//  BuyDepositRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the "Other Wallet" (direct USDC deposit) funding
/// path. Exercises the in-app flow end-to-end:
///
/// - The buy nested sheet opens on top of CurrencyInfoScreen.
/// - An amount above the USDF balance routes to `PurchaseMethodSheet`.
/// - Selecting "Other Wallet" pushes `USDCDepositEducationScreen`.
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

    func testDepositFlow_otherWallet_showsAddressScreen() {
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

        // Picker → Other Wallet → USDCDepositEducationScreen → Next.
        purchaseMethods.assertReached()
        purchaseMethods.selectOtherWallet(from: self)

        depositEducation.assertReached()
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
