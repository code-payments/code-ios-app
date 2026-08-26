//
//  WithdrawSmokeTests.swift
//  FlipcashUITests
//

import XCTest

final class WithdrawSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    /// The Wallet tab's "Withdraw Money" tile lands directly on the "Select
    /// Currency" picker, which lists every balance (Dollars included). USDF no
    /// longer gets a dedicated intro-first entry; the "Withdraw as USDC" screen
    /// is reached by picking Dollars.
    func testWithdraw_landsOnCurrencyPicker() {
        let wallet = WalletScreen(app: app)

        assertMainScreenReached()

        wallet.open(from: self)
        wallet.tapWithdrawMoneyTile(from: self)

        XCTAssertTrue(
            app.staticTexts["Select Currency"].waitForExistence(timeout: 10),
            "Expected the 'Select Currency' picker as the withdraw entry point"
        )
        // The old USDF-first intro and its escape hatch are gone.
        XCTAssertFalse(
            app.buttons["Withdraw Other Flipcash Currencies"].exists,
            "The 'other currencies' escape hatch should no longer exist — the picker is the entry"
        )
    }
}
