//
//  BuyApplePayRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the Apple Pay funding path's verification gate.
/// Exercises:
///
/// - The buy nested sheet opens on top of `CurrencyInfoScreen`.
/// - An amount above the USDF balance routes to `PurchaseMethodSheet`.
/// - Selecting Apple Pay on an unverified profile pushes `VerifyInfoScreen`
///   (sheet stacked on top of the buy sheet — not the Apple Pay overlay).
///
/// The test stops short of completing verification (SMS / email links are
/// out of scope for the simulator). Driving the actual Apple Pay sheet is
/// blocked by the unverified gate.
///
/// **Prerequisites:**
/// - `FLIPCASH_UI_TEST_ACCESS_KEY` set in `secrets.local.xcconfig`
/// - The account behind the access key must be **unverified** (no phone +
///   no email on the profile). A verified profile skips the gate and routes
///   straight to Apple Pay, which would fail this assertion.
final class BuyApplePayRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testApplePay_unverifiedAccount_showsVerificationSheet() {
        let wallet = WalletScreen(app: app)
        let currencyInfo = CurrencyInfoUIScreen(app: app)
        let amountEntry = AmountEntryScreen(app: app)
        let purchaseMethods = PurchaseMethodSheet(app: app)
        let verifyInfo = VerifyInfoUIScreen(app: app)

        assertMainScreenReached()

        // Navigate: Main → Wallet → first currency → CurrencyInfoScreen → Buy
        wallet.open(from: self)
        wallet.selectFirstCurrency()
        currencyInfo.assertReached()
        waitAndTap(currencyInfo.buyButton)

        // Enter a high amount so the USDF gate fails and the picker shows.
        amountEntry.enterPickerTriggeringAmount()
        waitUntilHittableAndTap(amountEntry.buyActionButton)

        // Picker → Apple Pay → VerifyInfoScreen (account is unverified).
        purchaseMethods.assertReached()
        purchaseMethods.selectApplePay(from: self)

        verifyInfo.assertReached()
    }
}
