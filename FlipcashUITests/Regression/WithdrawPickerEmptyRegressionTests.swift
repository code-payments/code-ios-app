//
//  WithdrawPickerEmptyRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Redesign guard: the withdraw picker now lists **every** balance, Dollars
/// included — USDF is no longer filtered out. A USDF-only account must therefore
/// show its Dollars row (and *not* the empty state, which is reserved for an
/// account with no displayable balances at all).
///
/// **Prerequisites:**
/// - `FLIPCASH_UI_TEST_USDF_ONLY_ACCESS_KEY` set in `secrets.local.xcconfig`
/// - The account behind the key must hold a displayable USDF balance and no
///   other currencies.
final class WithdrawPickerEmptyRegressionTests: BaseUITestCase {

    override var requiresUsdfOnlyAccount: Bool { true }

    func testWithdrawPicker_showsUsdfRow_onUsdfOnlyAccount() {
        let wallet = WalletScreen(app: app)

        assertMainScreenReached()

        wallet.open(from: self)
        wallet.tapWithdrawMoneyTile(from: self)

        XCTAssertTrue(
            app.staticTexts["Select Currency"].waitForExistence(timeout: 10),
            "Expected the 'Select Currency' picker as the withdraw entry point"
        )

        let currencyRows = app.buttons.matching(identifier: "currency-row")
        XCTAssertGreaterThanOrEqual(
            currencyRows.count, 1,
            "A USDF-only account must show its Dollars row — USDF is no longer filtered from the picker."
        )

        XCTAssertFalse(
            app.staticTexts["withdraw-picker-empty"].exists,
            "The empty state must not show when the account holds a displayable balance."
        )
    }
}
