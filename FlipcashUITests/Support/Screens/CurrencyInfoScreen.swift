//
//  CurrencyInfoScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for `CurrencyInfoScreen`'s action tiles.
///
/// The tab-bar UI renders `CurrencyInfoContentV2`, which gates the tiles on
/// whether the account holds the currency: Send / Buy / Transactions / More
/// when it does, a lone Buy In when it doesn't. Dollars drops Buy, since it is
/// the currency others are bought with. Convert and Withdraw live in the More
/// sheet.
@MainActor
struct CurrencyInfoUIScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    /// Tiles shown for a currency the account holds.
    var sendButton: XCUIElement { app.buttons["currency-tile-send"] }
    var transactionsButton: XCUIElement { app.buttons["currency-tile-transactions"] }
    var moreButton: XCUIElement { app.buttons["currency-tile-more"] }

    /// Shown for a held token; Dollars has no Buy tile.
    var buyButton: XCUIElement { app.buttons["currency-tile-buy"] }

    /// The only tile shown for a currency the account doesn't hold.
    var buyInButton: XCUIElement { app.buttons["currency-tile-buyIn"] }

    /// Rows in the More sheet.
    var convertRow: XCUIElement { app.buttons["currency-more-convert"] }
    var withdrawRow: XCUIElement { app.buttons["currency-more-withdraw"] }

    /// The currency's scrolling content, the container the lower sections are
    /// scrolled in.
    var scrollView: XCUIElement { app.scrollViews.firstMatch }

    /// Opens the per-token transaction history from its Transactions tile.
    func tapTransactions(from testCase: BaseUITestCase) {
        testCase.waitAndTap(transactionsButton)
    }

    /// Opens the More sheet and picks Convert.
    func tapConvert(from testCase: BaseUITestCase) {
        testCase.waitAndTap(moreButton)
        testCase.waitAndTap(convertRow, timeout: 10, "Expected Convert in the currency's More sheet")
    }

    // MARK: - Assertions

    /// Asserts the page for a currency the account holds.
    func assertHeldCurrencyReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            sendButton.waitForExistence(timeout: timeout),
            "Expected CurrencyInfoScreen for a held currency, with a Send tile"
        )
    }

    /// Asserts the page for a held currency that is *not* Dollars.
    ///
    /// Send is on both held layouts, so a test that only checks it cannot tell
    /// a token's page from the Dollars page — which is how a wallet tap that
    /// opened the wrong card used to pass. Buy is the tile only a token has.
    func assertHeldTokenReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            buyButton.waitForExistence(timeout: timeout),
            "Expected a held token's CurrencyInfoScreen, with a Buy tile — Dollars has none"
        )
    }

    /// Asserts the Dollars page, which has Send but no Buy tile.
    func assertDollarsReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            sendButton.waitForExistence(timeout: timeout),
            "Expected the Dollars CurrencyInfoScreen, with a Send tile"
        )
        XCTAssertFalse(
            buyButton.exists,
            "Expected the Dollars CurrencyInfoScreen — a token shows a Buy tile there"
        )
    }

    /// Asserts the page for a currency the account doesn't hold.
    func assertUnheldCurrencyReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            buyInButton.waitForExistence(timeout: timeout),
            "Expected CurrencyInfoScreen for an unheld currency, with a Buy In tile"
        )
    }
}
