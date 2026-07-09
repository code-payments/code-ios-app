//
//  BuyPhantomRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the Phantom deposit path. Buying is now reserves-only;
/// funding is the standalone Add Money flow. Exercises the in-app flow as far
/// as can be tested without a real Phantom install:
///
/// - The buy nested sheet opens on top of CurrencyInfoScreen.
/// - An amount above the USDF balance routes to the Add Money flow
///   ("No Balance Yet" → "Select Method").
/// - Selecting Phantom opens the "Add Money With Phantom" education screen
///   with the "Connect Your Phantom Wallet" CTA.
///
/// The test stops at the education screen: its CTA fires the Phantom connect
/// deeplink, and only a successful connect pushes "Amount to Add" — out of
/// scope for the local simulator without a real Phantom install.
///
/// **Prerequisites:**
/// - A valid `FLIPCASH_UI_TEST_ACCESS_KEY` set in `secrets.local.xcconfig`
final class BuyPhantomRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testPhantomFlow_showsEducationScreen() {
        let wallet = WalletScreen(app: app)
        let currencyInfo = CurrencyInfoUIScreen(app: app)
        let amountEntry = AmountEntryScreen(app: app)
        let addMoney = AddMoneyStartScreen(app: app)

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

        // No Balance Yet → Add Money → Select Method → Phantom → education.
        addMoney.assertNoBalanceReached()
        addMoney.tapAddMoney(from: self)
        addMoney.assertSelectMethodReached()
        addMoney.selectPhantom(from: self)

        addMoney.assertPhantomEducationReached()
    }
}
