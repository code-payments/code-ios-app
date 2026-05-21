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
        openDepositFromSettings()

        education.assertReached()
        XCTAssertTrue(education.nextButton.exists)
        XCTAssertTrue(education.depositOtherCurrenciesButton.exists)
    }

    func testDeposit_pickerKeepsUSDFAndRoutesToDirectAddress() {
        let education = USDCDepositEducationScreen(app: app)

        assertMainScreenReached()
        openDepositFromSettings()

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

    private func openDepositFromSettings() {
        let settings = SettingsUIScreen(app: app)
        settings.open(from: self)
        waitAndTap(settings.depositButton)
    }
}
