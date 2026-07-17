//
//  BuyApplePayRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the Add Money Apple Pay (Coinbase) path's
/// verified-contact gate: an unverified account tapping Add Money must land
/// on the verification sheet's first step, not the Apple Pay overlay. Which
/// step shows (phone vs email) depends on the account's server-side phone
/// state, so the test accepts either. Stops short of completing
/// verification — SMS / email links are out of scope for the simulator.
///
/// Entry is the Balance screen's own Add Money button — buy entry is capped
/// at the highest spendable balance, so the old buy-shortfall vehicle into
/// Add Money no longer exists.
///
/// **Prerequisites:**
/// - `FLIPCASH_UI_TEST_ACCESS_KEY` set in `secrets.local.xcconfig`
/// - The account behind the access key must have **no verified email**. A
///   verified email skips the gate and routes straight to Apple Pay, which
///   would fail this assertion.
/// - The account must have the Coinbase onramp enabled, or the Pay
///   row is hidden.
final class BuyApplePayRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testApplePay_unverifiedAccount_showsVerificationSheet() {
        let wallet = WalletScreen(app: app)
        let amountEntry = AmountEntryScreen(app: app)
        let addMoney = AddMoneyStartScreen(app: app)
        let verifyInfo = VerifyInfoUIScreen(app: app)

        assertMainScreenReached()

        // Navigate: Main → Wallet → Add Money → Select Method → Pay.
        wallet.open(from: self)
        waitUntilHittableAndTap(app.buttons["Add Money"].firstMatch)
        addMoney.assertSelectMethodReached()
        addMoney.selectPayDebitCard(from: self)

        // Amount to Add → enter $10 → the verified-contact gate opens the
        // verification sheet.
        addMoney.assertAmountToAddReached()
        amountEntry.keypadButton("1").tap()
        amountEntry.keypadButton("0").tap()
        waitUntilHittableAndTap(addMoney.amountToAddActionButton)

        verifyInfo.assertVerificationStepReached()
    }
}
