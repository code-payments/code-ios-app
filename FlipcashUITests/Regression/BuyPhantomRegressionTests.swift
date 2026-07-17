//
//  BuyPhantomRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the Phantom deposit path in the Add Money flow.
/// Exercises the in-app flow as far as can be tested without a real Phantom
/// install:
///
/// - The Balance screen's Add Money button opens "Select Method".
/// - Selecting Phantom opens the "Add Money With Phantom" education screen
///   with the "Connect Your Phantom Wallet" CTA.
///
/// The test stops at the education screen: its CTA fires the Phantom connect
/// deeplink, and only a successful connect pushes "Amount to Add" — out of
/// scope for the local simulator without a real Phantom install.
///
/// Entry is the Balance screen's own Add Money button — buy entry is capped
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

        // Navigate: Main → Wallet → Add Money → Select Method → Phantom.
        wallet.open(from: self)
        waitUntilHittableAndTap(app.buttons["Add Money"].firstMatch)
        addMoney.assertSelectMethodReached()
        addMoney.selectPhantom(from: self)

        addMoney.assertPhantomEducationReached()
    }
}
