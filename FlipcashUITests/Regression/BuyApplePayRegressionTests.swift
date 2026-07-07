//
//  BuyApplePayRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the Add Money Apple Pay (Coinbase) path's verification
/// gate. Buying is reserves-only; funding is the standalone Add Money flow,
/// and the `$5`-minimum + verified-contact gate moved onto
/// `CoinbaseDepositOperation`. Exercises:
///
/// - The buy nested sheet opens on top of `CurrencyInfoScreen`.
/// - An amount above the USDF balance routes to the Add Money flow.
/// - Picking Pay pushes "Amount to Add"; tapping Add Money there on an
///   unverified profile opens the verification sheet directly on the Enter
///   Phone step (no intro page — not the Apple Pay overlay).
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

        // Amount to Add → enter $10 → Add Money runs the verified-contact
        // gate, which opens the verification sheet for the unverified account
        // directly on the Enter Phone step. The buy keypad is still mounted
        // beneath the stacked Add Money chain, so the digits must target the
        // topmost keypad.
        addMoney.assertAmountToAddReached()
        amountEntry.stackedKeypadButton("1").tap()
        amountEntry.stackedKeypadButton("0").tap()
        waitUntilHittableAndTap(addMoney.amountToAddActionButton)

        verifyInfo.assertPhoneStepReached()
    }
}
