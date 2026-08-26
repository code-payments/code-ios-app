//
//  BuyApplePayRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the Add Money debit-card (Coinbase) path's
/// verified-contact gate: an unverified account picking Debit Card must land
/// on the verification flow's first step, not on an amount screen or the
/// Apple Pay overlay. The gate runs up front — before "Amount to Add" — so
/// no empty screen appears ahead of it. Which step shows (phone vs email)
/// depends on the account's server-side phone state, so the test accepts
/// either. Stops short of completing verification — SMS / email links are
/// out of scope for the simulator.
///
/// Entry is the Wallet tab's own Add Money tile — buy entry is capped
/// at the highest spendable balance, so the old buy-shortfall vehicle into
/// Add Money no longer exists.
///
/// **Prerequisites:**
/// - `FLIPCASH_UI_TEST_ACCESS_KEY` set in `secrets.local.xcconfig`
/// - The account behind the access key must have **no verified email**. A
///   verified email skips the gate and routes straight to "Amount to Add",
///   which would fail this assertion.
/// - The account must have the Coinbase onramp enabled, or the Debit Card
///   row is hidden.
final class BuyApplePayRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testApplePay_unverifiedAccount_showsVerificationSheet() {
        let wallet = WalletScreen(app: app)
        let addMoney = AddMoneyStartScreen(app: app)
        let verifyInfo = VerifyInfoUIScreen(app: app)

        assertMainScreenReached()

        // Navigate: Wallet tab → Add Money tile → Add Money With → Debit Card.
        wallet.open(from: self)
        wallet.tapAddMoneyTile(from: self)
        addMoney.assertMethodPickerReached()
        addMoney.selectPayDebitCard(from: self)

        // The gate fires on selection, so the verification step is the next
        // screen — there is no amount entry to step through first.
        verifyInfo.assertVerificationStepReached()
    }
}
