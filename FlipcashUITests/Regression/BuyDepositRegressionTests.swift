//
//  BuyDepositRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the "Other Wallet" deposit path in the Add Money flow.
/// Buying is reserves-only; funding is the standalone Add Money flow. The old
/// "Deposit USDC" picker row is now the "Other Wallet" method, which opens the
/// USDC education pre-flight; Next pushes the deposit-address screen. Exercises:
///
/// - The buy nested sheet opens on top of CurrencyInfoScreen.
/// - An amount above the USDF balance routes to the Add Money flow.
/// - Selecting Other Wallet shows the USDC education screen; Next pushes the
///   deposit-address screen with the Copy Address button hittable. The address
///   is derived from the session's owner key — its exact value isn't asserted,
///   just that the CTA renders.
///
/// **Prerequisites:**
/// - A valid `FLIPCASH_UI_TEST_ACCESS_KEY` set in `secrets.local.xcconfig`
/// - The test account must have at least one non-USDF currency visible in
///   Wallet (the first row is used as the buy target).
final class BuyDepositRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testOtherWallet_pushesUSDCDepositAddress() {
        let wallet = WalletScreen(app: app)
        let currencyInfo = CurrencyInfoUIScreen(app: app)
        let amountEntry = AmountEntryScreen(app: app)
        let addMoney = AddMoneyStartScreen(app: app)
        let education = USDCDepositEducationScreen(app: app)
        let depositAddress = USDCDepositAddressScreen(app: app)

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

        // No Balance Yet → Add Money → Select Method → Other Wallet →
        // USDC education pre-flight → Next → USDC deposit-address screen.
        addMoney.assertNoBalanceReached()
        addMoney.tapAddMoney(from: self)
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
