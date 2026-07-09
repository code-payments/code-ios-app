//
//  BuyApplePayRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the Add Money Apple Pay (Coinbase) path's
/// verified-contact gate: an unverified account tapping Add Money must land
/// on the verification sheet's Enter Phone step, not the Apple Pay overlay.
/// Stops short of completing verification — SMS / email links are out of
/// scope for the simulator.
///
/// **Prerequisites:**
/// - `FLIPCASH_UI_TEST_ACCESS_KEY` set in `secrets.local.xcconfig`
/// - The account behind the access key must be **unverified** (no phone +
///   no email on the profile). A verified profile skips the gate and routes
///   straight to Apple Pay, which would fail this assertion.
/// - The account must have the Coinbase onramp enabled, or the Pay
///   row is hidden.
final class BuyApplePayRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testApplePay_unverifiedAccount_showsVerificationSheet() {
        let wallet = WalletScreen(app: app)
        let currencyInfo = CurrencyInfoUIScreen(app: app)
        let amountEntry = AmountEntryScreen(app: app)
        let addMoney = AddMoneyStartScreen(app: app)
        let verifyInfo = VerifyInfoUIScreen(app: app)

        assertMainScreenReached()

        // Navigate: Main → Wallet → first currency → CurrencyInfoScreen → Buy
        wallet.open(from: self)
        wallet.selectFirstCurrency()
        currencyInfo.assertReached()
        waitAndTap(currencyInfo.buyButton)

        // Enter an amount above the USDF balance so the buy shortfall routes
        // into the Add Money flow.
        amountEntry.enterPickerTriggeringAmount()
        waitUntilHittableAndTap(amountEntry.buyActionButton)

        // No Balance Yet → Add Money → Select Method → Pay.
        addMoney.assertNoBalanceReached()
        addMoney.tapAddMoney(from: self)
        addMoney.assertSelectMethodReached()
        addMoney.selectPayDebitCard(from: self)

        // Amount to Add → enter $10 → the verified-contact gate opens the
        // verification sheet. The buy keypad was navigated away, so only one
        // keypad is in the hierarchy.
        addMoney.assertAmountToAddReached()
        amountEntry.keypadButton("1").tap()
        amountEntry.keypadButton("0").tap()
        waitUntilHittableAndTap(addMoney.amountToAddActionButton)

        verifyInfo.assertPhoneStepReached()
    }
}
