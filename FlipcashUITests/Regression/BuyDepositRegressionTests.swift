//
//  BuyDepositRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the "Other Wallet" deposit path in the Add Money flow.
/// The old "Deposit USDC" picker row is the "Other Wallet" method, which opens
/// the USDC education pre-flight; Next pushes the deposit-address screen.
/// Exercises:
///
/// - The Balance screen's Add Money button opens "Select Method".
/// - Selecting Other Wallet shows the USDC education screen; Next pushes the
///   deposit-address screen with the Copy Address button hittable. The address
///   is derived from the session's owner key — its exact value isn't asserted,
///   just that the CTA renders.
///
/// Entry is the Balance screen's own Add Money button — buy entry is capped
/// at the highest spendable balance, so the old buy-shortfall vehicle into
/// Add Money no longer exists.
///
/// **Prerequisites:**
/// - A valid `FLIPCASH_UI_TEST_ACCESS_KEY` set in `secrets.local.xcconfig`
final class BuyDepositRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testOtherWallet_pushesUSDCDepositAddress() {
        let wallet = WalletScreen(app: app)
        let addMoney = AddMoneyStartScreen(app: app)
        let education = USDCDepositEducationScreen(app: app)
        let depositAddress = USDCDepositAddressScreen(app: app)

        assertMainScreenReached()

        // Navigate: Main → Wallet → Add Money → Select Method → Other Wallet →
        // USDC education pre-flight → Next → USDC deposit-address screen.
        wallet.open(from: self)
        waitUntilHittableAndTap(app.buttons["Add Money"].firstMatch)
        addMoney.assertSelectMethodReached()
        addMoney.selectOtherWallet(from: self)

        education.assertReached()
        education.tapNext(from: self)

        depositAddress.assertReached()
        XCTAssertTrue(
            depositAddress.copyAddressButton.isHittable,
            "Expected the Copy Address CTA to be hittable"
        )
    }
}
