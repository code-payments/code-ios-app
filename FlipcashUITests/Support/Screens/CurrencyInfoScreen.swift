//
//  CurrencyInfoScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for `CurrencyInfoScreen`'s action tiles.
///
/// The tab-bar UI renders `CurrencyInfoContentV2`, which gates the tiles on
/// whether the account holds the currency: Give / Buy More / Convert when it
/// does, a lone Buy In when it doesn't. Dollars keeps its own held row —
/// Give / Convert / Withdraw — since it is the currency others are bought with.
@MainActor
struct CurrencyInfoUIScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    /// Tiles shown for a currency the account holds.
    var giveButton: XCUIElement { app.buttons["Give"] }
    var buyMoreButton: XCUIElement { app.buttons["Buy More"] }
    var convertButton: XCUIElement { app.buttons["Convert"] }

    /// Shown in place of Buy More on Dollars.
    var withdrawButton: XCUIElement { app.buttons["Withdraw"] }

    /// The only tile shown for a currency the account doesn't hold.
    var buyInButton: XCUIElement { app.buttons["Buy In"] }

    /// The currency's scrolling content, the container the lower sections are
    /// scrolled in.
    var scrollView: XCUIElement { app.scrollViews.firstMatch }

    /// Opens the per-token transaction history. In the tab-bar UI that is the
    /// "Recent" section header (`RecentActivitySection.onShowAll`) — the rows
    /// under it are a non-interactive preview, and the v1 "Transaction History"
    /// button went with the old footer.
    var recentActivityHeader: XCUIElement { app.buttons["Recent"] }

    // MARK: - Actions

    /// Scrolls the "Recent" header into view and taps it, opening the full
    /// per-token history. It sits below the hero card and the action tiles, so
    /// it starts off-screen.
    func tapRecentActivityHeader(from testCase: BaseUITestCase) {
        testCase.scrollUpToAndTap(recentActivityHeader, in: scrollView)
    }

    // MARK: - Assertions

    /// Asserts the page for a currency the account holds.
    func assertHeldCurrencyReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            convertButton.waitForExistence(timeout: timeout),
            "Expected CurrencyInfoScreen for a held currency, with a Convert tile"
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
