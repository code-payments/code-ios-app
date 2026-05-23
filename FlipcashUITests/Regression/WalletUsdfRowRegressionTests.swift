//
//  WalletUsdfRowRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression: the wallet must display the USDF row when USDF holds a
/// displayable balance. A prior refactor collapsed the separate "reserves"
/// row into the unified `sortedBalances` list but kept a `hasBalances` gate
/// that ignored USDF, so a USDF-only-funded wallet rendered the
/// "No Balance Yet" empty state even though the user had ~$1 USDF.
///
/// **Prerequisites:**
/// - `FLIPCASH_UI_TEST_USDF_ONLY_ACCESS_KEY` set in `secrets.local.xcconfig`
/// - The account behind the key must hold a displayable USDF balance and
///   **no** non-USDF currencies (the test asserts on the USDF row
///   specifically; mixed-funding accounts are covered by other regression
///   tests).
final class WalletUsdfRowRegressionTests: BaseUITestCase {

    override var requiresUsdfOnlyAccount: Bool { true }

    func testWallet_displaysUsdfRow_onUsdfOnlyAccount() {
        let wallet = WalletScreen(app: app)

        assertMainScreenReached()
        wallet.open(from: self)

        XCTAssertTrue(
            wallet.usdfRow.waitForExistence(timeout: 30),
            "USDF row must be visible when the wallet holds displayable USDF — regression of the hasBalances gate that ignored USDF."
        )

        let usdfRows = app.buttons.matching(identifier: "currency-row-usdf")
        XCTAssertEqual(
            usdfRows.count, 1,
            "Expected exactly one USDF row, found \(usdfRows.count)."
        )

        let otherCurrencyRows = app.buttons.matching(identifier: "currency-row")
        XCTAssertEqual(
            otherCurrencyRows.count, 0,
            "USDF-only account must not show non-USDF currency rows, found \(otherCurrencyRows.count)."
        )
    }
}
