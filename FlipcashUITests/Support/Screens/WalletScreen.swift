//
//  WalletScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the Wallet tab: the balance header, the deck of per-currency
/// bill cards, and the tile shortcuts below the recent activity.
@MainActor
struct WalletScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    /// The wallet's scrolling content, the container the tiles are scrolled in.
    var scrollView: XCUIElement { app.scrollViews.firstMatch }

    /// The first non-USDF currency card. Identified by the card's accessibility
    /// identifier rather than `app.cells`, since the wallet is a `ScrollView` of
    /// stacked cards rather than a `List`. The USDF card carries the distinct
    /// identifier "currency-row-usdf" so this selector reliably targets an
    /// investable token regardless of where USDF sorts.
    var firstCurrencyRow: XCUIElement {
        app.buttons.matching(identifier: "currency-row").firstMatch
    }

    /// The USDF card in the wallet. Always present once balances have synced.
    var usdfRow: XCUIElement {
        app.buttons["currency-row-usdf"]
    }

    /// The balance header button that shows the flag + total amount + chevron.
    var balanceHeader: XCUIElement { app.buttons["balance-header"] }

    /// The "Add Money" tile. Matched by identifier, not label: the new-user
    /// tutorial above it renders an "Add Money" row too, and on a funded account
    /// that row is completed and therefore disabled.
    var addMoneyTile: XCUIElement { app.buttons["wallet-tile-add-money"] }

    // MARK: - Actions

    /// Opens the Wallet tab and waits for it to load.
    func open(from testCase: BaseUITestCase) {
        testCase.waitAndTap(app.buttons["Wallet"])
    }

    /// Taps the balance header to open the region selection sheet.
    func tapBalanceHeader(from testCase: BaseUITestCase) {
        testCase.waitAndTap(balanceHeader)
    }

    /// Scrolls the "Add Money" tile into view and taps it. The tiles sit below
    /// the card deck and the recent activity, so they start off-screen.
    func tapAddMoneyTile(from testCase: BaseUITestCase) {
        testCase.scrollUpToAndTap(addMoneyTile, in: scrollView)
    }

    /// Selects the first currency card and verifies CurrencyInfoScreen is reached.
    func selectFirstCurrency() {
        XCTAssertTrue(
            firstCurrencyRow.waitForExistence(timeout: 30),
            "Expected at least one currency in the Wallet"
        )
        firstCurrencyRow.tap()
    }
}
