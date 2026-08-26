//
//  AddMoneyGateRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the reserves-only buy gate: an account with nothing
/// spendable must still reach the Get amount screen, where
/// `BuyAmountViewModel.actionTitle` swaps Next for an Add Money CTA.
///
/// **Skipped: no fixture can reach it.** The gate needs an account with no
/// spendable balance, and the tab-bar UI gives such an account no door to a
/// currency's Get button:
///
/// - The Wallet's Discover tile is drawn only for
///   `session.hasEverAddedMoney()`, which is exactly the accounts the gate does
///   not apply to; an unfunded account gets the new-user tutorial instead.
/// - `flipcash://discover` routes to the same destination, but `app.open`
///   relaunches the app and a freshly created account does not survive the
///   relaunch — the app comes back on "Create a New Account".
/// - The standing `FLIPCASH_UI_TEST_ACCESS_KEY` and USDF-only accounts both
///   hold displayable USDF, so `paymentOptions` is non-empty and the button
///   reads Next.
///
/// The gate itself is live: a funded account spent down to nothing hits it. The
/// test needs a spent-down fixture that the suite doesn't have.
final class AddMoneyGateRegressionTests: BaseUITestCase {

    func testBuyWithNoAssets_offersAddMoneyOnAmountEntry() throws {
        throw XCTSkip("Needs a spent-down account: the Get screen has no entry from a $0 balance in the tab-bar UI")
    }
}
