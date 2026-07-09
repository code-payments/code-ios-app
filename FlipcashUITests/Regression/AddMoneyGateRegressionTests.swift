//
//  AddMoneyGateRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression tests for the reserves-only gates: an account with no USDF must
/// route through "No Balance Yet" → Add Money instead of entering the buy or
/// create flow. Uses fresh-account creation for a guaranteed $0 balance, so
/// no auth keys are required.
final class AddMoneyGateRegressionTests: BaseUITestCase {

    func testBuyWithNoAssets_gatesOnAddMoneyBeforeAmountEntry() {
        let addMoney = AddMoneyStartScreen(app: app)
        let currencyInfo = CurrencyInfoUIScreen(app: app)

        createFreshAccount()

        // Discover → first leaderboard currency → CurrencyInfoScreen.
        waitAndTap(app.buttons["scan-discover-button"])
        waitUntilHittableAndTap(
            app.buttons.matching(identifier: "discover-leaderboard-row").firstMatch,
            "Expected the Discover leaderboard to list at least one currency"
        )
        currencyInfo.assertReached()

        // Buy on a $0 account must gate immediately — no amount sheet.
        waitAndTap(currencyInfo.buyButton)
        addMoney.assertNoBalanceReached()
        XCTAssertTrue(
            app.staticTexts["Add money to buy currencies"].exists,
            "Expected the buy-context subtitle on the No Balance prompt"
        )
        XCTAssertFalse(
            app.navigationBars["Amount"].exists,
            "The buy amount sheet must not open when the account has no USDF"
        )

        // Add Money → the Select Method picker.
        addMoney.tapAddMoney(from: self)
        addMoney.assertSelectMethodReached()
    }

    func testCreateCurrencyWithNoAssets_gatesOnAddMoney() {
        let addMoney = AddMoneyStartScreen(app: app)

        createFreshAccount()

        // Discover → promo card → Create Your Currency summary.
        waitAndTap(app.buttons["scan-discover-button"])
        waitUntilHittableAndTap(
            app.buttons["discover-create-currency-card"],
            "Expected the Create-Your-Own-Currency promo card"
        )
        XCTAssertTrue(
            app.navigationBars["Create Your Currency"].waitForExistence(timeout: 10),
            "Expected the currency creation summary screen"
        )

        // Get Started on a $0 account must gate on Add Money, not enter the wizard.
        waitUntilHittableAndTap(app.buttons["Get Started"])
        addMoney.assertNoBalanceReached()
        XCTAssertTrue(
            app.staticTexts["Add money to create a currency"].exists,
            "Expected the create-context subtitle on the No Balance prompt"
        )

        // Add Money → the Select Method picker.
        addMoney.tapAddMoney(from: self)
        addMoney.assertSelectMethodReached()
    }

    /// Walks the fastest fresh-account path (write-down branch, no Photos
    /// permission needed) so each test starts from a guaranteed $0 balance.
    private func createFreshAccount() {
        waitAndTap(app.buttons["Create a New Account"])
        waitAndTap(app.buttons["Wrote the 12 Words Down Instead?"])
        waitAndTap(app.buttons["Yes, I Wrote Them Down"])
        allowPhoneVerificationIfNeeded()
        allowContactsIfNeeded()
        allowPushNotificationsIfNeeded()
        assertMainScreenReached()
    }
}
