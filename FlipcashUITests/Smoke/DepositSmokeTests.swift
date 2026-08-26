//
//  DepositSmokeTests.swift
//  FlipcashUITests
//

import XCTest

final class DepositSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testDeposit_landsOnUSDCEducationScreenWithBothButtons() {
        let education = USDCDepositEducationScreen(app: app)

        assertMainScreenReached()
        openDeposit()

        education.assertReached()
        XCTAssertTrue(education.nextButton.exists)
        XCTAssertTrue(education.depositOtherCurrenciesButton.exists)
    }

    func testDeposit_pickerKeepsUSDFAndRoutesToDirectAddress() {
        let education = USDCDepositEducationScreen(app: app)

        assertMainScreenReached()
        openDeposit()

        education.tapDepositOtherCurrencies(from: self)

        XCTAssertTrue(
            app.staticTexts["Select Currency"].waitForExistence(timeout: 10),
            "Expected the 'Select Currency' picker after tapping the escape hatch"
        )

        let usdfRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'USDF,'")).firstMatch
        XCTAssertTrue(
            usdfRow.waitForExistence(timeout: 10),
            "USDF row must appear in the deposit picker"
        )
        usdfRow.tap()

        XCTAssertTrue(
            app.buttons["Copy Address"].waitForExistence(timeout: 10),
            "Expected `DepositScreen` with 'Copy Address' CTA after picking USDF"
        )
        XCTAssertFalse(
            app.buttons["Next"].exists,
            "USDF in the picker must not re-enter the USDC education flow"
        )
    }

    // MARK: - Helpers

    /// Wallet tile → Add Money → Other Wallet, landing on the USDC education
    /// screen the old Settings Deposit row used to open directly.
    private func openDeposit() {
        let wallet = WalletScreen(app: app)
        let addMoney = AddMoneyStartScreen(app: app)
        wallet.open(from: self)
        wallet.tapAddMoneyTile(from: self)
        addMoney.assertMethodPickerReached()
        addMoney.selectOtherWallet(from: self)
    }
}
