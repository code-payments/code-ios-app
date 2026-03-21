//
//  WalletScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the Wallet (BalanceScreen).
/// Lists owned currencies and USDF reserves.
@MainActor
struct WalletScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    /// The first actual currency row. Index 0 is the List section header
    /// (total balance + appreciation); currency rows start at index 1.
    var firstCurrencyRow: XCUIElement { app.cells.element(boundBy: 1) }

    // MARK: - Actions

    /// Opens the Wallet sheet from the main screen and waits for it to load.
    func open(from testCase: BaseUITestCase) {
        testCase.waitAndTap(app.buttons["Wallet"])
    }

    /// Selects the first currency row and verifies CurrencyInfoScreen is reached.
    func selectFirstCurrency() {
        XCTAssertTrue(
            firstCurrencyRow.waitForExistence(timeout: 30),
            "Expected at least one currency in the Wallet"
        )
        firstCurrencyRow.tap()
    }
}
