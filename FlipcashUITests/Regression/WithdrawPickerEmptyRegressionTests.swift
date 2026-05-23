//
//  WithdrawPickerEmptyRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression: the "Withdraw Other Flipcash Currencies" picker must show
/// an empty state when the user has no non-USDF currencies. Previously the
/// screen rendered a blank black void under the navigation title because
/// the `List`'s `ForEach` produced zero rows and the body had no
/// empty-state branch.
///
/// **Prerequisites:**
/// - `FLIPCASH_UI_TEST_USDF_ONLY_ACCESS_KEY` set in `secrets.local.xcconfig`
/// - The account behind the key must hold a displayable USDF balance and
///   **no** non-USDF currencies (the picker filters USDF out by design;
///   any non-USDF mint would populate the list and bypass the empty state).
final class WithdrawPickerEmptyRegressionTests: BaseUITestCase {

    override var requiresUsdfOnlyAccount: Bool { true }

    func testWithdrawPicker_showsEmptyState_onUsdfOnlyAccount() {
        let settings = SettingsUIScreen(app: app)

        assertMainScreenReached()

        settings.open(from: self)
        waitAndTap(settings.withdrawButton)
        waitAndTap(app.buttons["Withdraw Other Flipcash Currencies"])

        let emptyState = app.staticTexts["withdraw-picker-empty"]
        XCTAssertTrue(
            emptyState.waitForExistence(timeout: 10),
            "Withdraw picker must show the empty-state text when no non-USDF currencies are held — regression of the blank picker bug."
        )

        let currencyRows = app.buttons.matching(identifier: "currency-row")
        XCTAssertEqual(
            currencyRows.count, 0,
            "No currency rows should render alongside the empty state."
        )
    }
}
