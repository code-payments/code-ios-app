//
//  WalletScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the Wallet tab: the balance header, the deck of per-currency
/// bill cards, and the tile shortcuts below the recent activity.
@MainActor
struct WalletScreen {

    /// How far below a card's top edge to tap: half the deck's 64pt per-card
    /// reveal, so the point sits inside the strip no card overlaps.
    private static let visibleStripInset: CGFloat = 32

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
    ///
    /// Tap it with ``selectFirstCurrency()``, never with `tap()` — see
    /// ``tapVisibleStrip(of:)``.
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

    /// The "Withdraw Money" tile, which pushes the currency picker onto the
    /// wallet's own stack.
    var withdrawMoneyTile: XCUIElement { app.buttons["wallet-tile-withdraw-money"] }

    /// The "Discover Currencies" tile, which pushes the leaderboard onto the
    /// wallet's own stack — v1 opened it as a sheet off the scanner.
    var discoverCurrenciesTile: XCUIElement { app.buttons["wallet-tile-discover-currencies"] }

    /// The "Create a Currency" tile, which pushes the creation summary directly.
    /// It replaces Discover's promo card, which the tab-bar UI hides
    /// (`CurrencyDiscoveryScreen.hidesPromo`).
    var createCurrencyTile: XCUIElement { app.buttons["wallet-tile-create-currency"] }

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

    /// Scrolls the "Withdraw Money" tile into view and taps it.
    func tapWithdrawMoneyTile(from testCase: BaseUITestCase) {
        testCase.scrollUpToAndTap(withdrawMoneyTile, in: scrollView)
    }

    func tapDiscoverCurrenciesTile(from testCase: BaseUITestCase) {
        testCase.scrollUpToAndTap(discoverCurrenciesTile, in: scrollView)
    }

    func tapCreateCurrencyTile(from testCase: BaseUITestCase) {
        testCase.scrollUpToAndTap(createCurrencyTile, in: scrollView)
    }

    /// Opens the first non-USDF currency's info page.
    func selectFirstCurrency() {
        XCTAssertTrue(
            firstCurrencyRow.waitForExistence(timeout: 30),
            "Expected at least one currency in the Wallet"
        )
        tapVisibleStrip(of: firstCurrencyRow)
    }

    /// Opens the USDF (Dollars) info page — the source for a convert that buys
    /// more of a currency the account already holds.
    ///
    /// Dollars needs the strip tap as much as a token does: it sorts by value
    /// like every other card, so anything worth less is drawn on top of it and
    /// a centre tap opens that card instead.
    func selectUsdfCurrency() {
        XCTAssertTrue(
            usdfRow.waitForExistence(timeout: 30),
            "Expected the USDF card in the Wallet"
        )
        tapVisibleStrip(of: usdfRow)
    }

    /// Taps the middle of a card's uncovered top strip.
    ///
    /// `TokenCardStack` lays the cards coincident and offsets each one
    /// `fannedReveal` (64pt) below the card behind it, so all a card leaves
    /// uncovered is that top sliver — the frame centre `XCUIElement.tap()` aims
    /// at belongs to the card in front, which is the one the tap then opens. A
    /// covered card still reports `isHittable == true`, so there is nothing to
    /// assert here; the guard is `assertHeldTokenReached()` at the destination.
    ///
    /// The offset is in points from the top edge rather than a fraction of the
    /// frame, because the Dollars card's watermark overflows its bounds and
    /// inflates its accessibility frame — the same fraction lands lower there
    /// than on a plain card.
    private func tapVisibleStrip(of card: XCUIElement) {
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: Self.visibleStripInset))
            .tap()
    }
}
