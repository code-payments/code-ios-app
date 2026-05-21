//
//  WithdrawSmokeTests.swift
//  FlipcashUITests
//

import XCTest

final class WithdrawSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    /// Settings → Withdraw lands on the USDC education screen with USDF
    /// pre-selected as the source, and exposes a subtle "Withdraw Other
    /// Flipcash Currencies" escape hatch.
    func testWithdraw_landsOnUSDCEducationScreenWithBothButtons() {
        assertMainScreenReached()

        openWithdrawFromSettings()

        XCTAssertTrue(
            app.staticTexts["Withdraw as USDC"].waitForExistence(timeout: 10),
            "Expected the USDC education screen as the withdraw entry point"
        )
        XCTAssertTrue(app.buttons["Next"].exists, "Expected the primary Next button")
        XCTAssertTrue(
            app.buttons["Withdraw Other Flipcash Currencies"].exists,
            "Expected the subtle 'Withdraw Other Flipcash Currencies' escape hatch below Next"
        )
    }

    /// Tapping the escape hatch pushes the currency picker, and USDF is
    /// absent from the list — USDF is reached exclusively via the intro
    /// screen's Next button, so listing it in the picker would create two
    /// paths to the same flow.
    func testWithdraw_otherCurrenciesPickerHidesUSDF() {
        assertMainScreenReached()

        openWithdrawFromSettings()

        waitAndTap(app.buttons["Withdraw Other Flipcash Currencies"])

        XCTAssertTrue(
            app.staticTexts["Select Currency"].waitForExistence(timeout: 10),
            "Expected the 'Select Currency' picker after tapping the escape hatch"
        )

        // Picker rows have accessibility labels of the form "<name>, $<amount>".
        // USDF is the only mint the picker is required to hide; any other
        // mint listed here is account-dependent and not asserted on.
        let usdfRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'USDF,'"))
        XCTAssertEqual(usdfRow.count, 0, "USDF must not appear in the 'other currencies' picker")
    }

    // MARK: - Helpers

    private func openWithdrawFromSettings() {
        let settings = SettingsUIScreen(app: app)
        settings.open(from: self)
        waitAndTap(settings.withdrawButton)
    }
}
