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

    /// The first currency row. Identified by the row's accessibility identifier
    /// rather than `app.cells`, since the wallet uses a `ScrollView` + `LazyVStack`
    /// rather than a `List`.
    var firstCurrencyRow: XCUIElement {
        app.buttons.matching(identifier: "currency-row").firstMatch
    }

    /// The balance header button that shows the flag + total amount + chevron.
    var balanceHeader: XCUIElement { app.buttons["balance-header"] }

    // MARK: - Actions

    /// Opens the Wallet sheet from the main screen and waits for it to load.
    func open(from testCase: BaseUITestCase) {
        testCase.waitAndTap(app.buttons["Wallet"])
    }

    /// Taps the balance header to open the region selection sheet.
    func tapBalanceHeader(from testCase: BaseUITestCase) {
        testCase.waitAndTap(balanceHeader)
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
