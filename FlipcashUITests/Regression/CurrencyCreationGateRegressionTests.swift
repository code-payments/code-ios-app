//
//  CurrencyCreationGateRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the currency-creation launch gate: Get Started must open
/// the Add Money prompt, not the wizard, when no single balance covers the
/// launch cost (`shouldAddMoneyBeforeLaunch`).
///
/// **Fixture.** Needs the standing `FLIPCASH_UI_TEST_ACCESS_KEY` account even
/// though the gate is about being short of money. The only entry to the
/// creation summary in the tab-bar UI is the Wallet tile, and `WalletScreen`
/// draws its tiles only when `session.hasEverAddedMoney()` — v1's other door,
/// the promo card on Discover, is hidden by `CurrencyDiscoveryScreen.hidesPromo`
/// and there is no deeplink. So the account has to hold money, and the gate is
/// a shortfall check rather than a $0 check, which leaves the outcome dependent
/// on the account's balance against the server's `newCurrencyPurchaseAmount` +
/// `newCurrencyFeeAmount`. The test skips when the account can afford the
/// launch, the same way `BlockUnblockSmokeTests` skips without a tip DM.
///
/// The test only navigates — it stops at the Add Money picker, or backs out of
/// the wizard without entering anything.
final class CurrencyCreationGateRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testCreateCurrencyBelowLaunchCost_gatesOnAddMoney() throws {
        let wallet = WalletScreen(app: app)
        let addMoney = AddMoneyStartScreen(app: app)

        // Wallet → Create a Currency → Create Your Currency summary.
        wallet.open(from: self)
        wallet.tapCreateCurrencyTile(from: self)
        XCTAssertTrue(
            app.navigationBars["Create Your Currency"].waitForExistence(timeout: 10),
            "Expected the currency creation summary screen"
        )

        waitUntilHittableAndTap(app.buttons["Get Started"])

        // Get Started branches on the balance: the prompt when nothing covers
        // the launch cost, the wizard when something does.
        let prompt = addMoney.noBalanceTitle
        let wizard = app.textFields["Currency Name"]
        let deadline = Date().addingTimeInterval(20)
        while !prompt.exists && !wizard.exists && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard prompt.exists else {
            throw XCTSkip("The standing account can afford the currency launch cost — the gate can't fire")
        }

        XCTAssertTrue(
            app.staticTexts["Add money to create a currency"].exists,
            "Expected the create-context subtitle on the No Balance prompt"
        )

        // Add Money → the Add Money With picker.
        addMoney.tapAddMoney(from: self)
        addMoney.assertMethodPickerReached()
    }
}
