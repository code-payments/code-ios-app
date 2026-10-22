//
//  BuyPhantomRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the Phantom deposit path in the Add Money flow.
/// Exercises the in-app flow as far as can be tested without a real Phantom
/// install:
///
/// - The Wallet tab's Add Dollars tile opens the "Add Dollars With" picker.
/// - Selecting Phantom opens the "Add Money With Phantom" education screen
///   with the "Connect Your Phantom Wallet" CTA.
///
/// The test stops at the education screen: its CTA fires the Phantom connect
/// deeplink, and only a successful connect pushes "Amount to Add" — out of
/// scope for the local simulator without a real Phantom install.
///
/// Entry is the Wallet tab's own Add Dollars tile — buy entry is capped
/// at the highest spendable balance, so the old buy-shortfall vehicle into
/// Add Money no longer exists.
///
/// **Prerequisites:**
/// - A valid `FLIPCASH_UI_TEST_ACCESS_KEY` set in `secrets.local.xcconfig`
final class BuyPhantomRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testPhantomFlow_showsEducationScreen() {
        let wallet = WalletScreen(app: app)
        let addMoney = AddMoneyStartScreen(app: app)

        assertMainScreenReached()

        // Navigate: Wallet tab → Add Dollars tile → Add Dollars With → Phantom.
        wallet.open(from: self)
        wallet.tapAddMoneyTile(from: self)
        addMoney.assertMethodPickerReached()
        addMoney.selectPhantom(from: self)

        addMoney.assertPhantomEducationReached()
    }
}
