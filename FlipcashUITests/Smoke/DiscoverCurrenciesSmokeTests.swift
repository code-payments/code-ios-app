//
//  DiscoverCurrenciesSmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// Covers the two currency-discovery tiles on the Wallet tab: Discover
/// Currencies opens the leaderboard, and Create a Currency opens the creation
/// summary.
///
/// The v1 pair was one route — Discover, opened as a sheet off the scanner, with
/// currency creation reached from the promo card at the top of its list. The
/// tab-bar UI splits them into sibling tiles and hides the promo card
/// (`CurrencyDiscoveryScreen.hidesPromo`), so the entries are checked side by
/// side rather than one through the other.
///
/// **Fixture.** Needs the standing `FLIPCASH_UI_TEST_ACCESS_KEY` account rather
/// than a fresh one: `WalletScreen` draws the tiles only when
/// `session.hasEverAddedMoney()` is true, and gives an unfunded account the
/// new-user tutorial in their place. The test only navigates, so it leaves the
/// account untouched.
final class DiscoverCurrenciesSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testWalletTiles_openDiscoverAndCurrencyCreation() throws {
        let wallet = WalletScreen(app: app)

        // MARK: Discover Currencies → the leaderboard.
        wallet.open(from: self)
        wallet.tapDiscoverCurrenciesTile(from: self)

        XCTAssertTrue(
            app.navigationBars["Discover Currencies"].waitForExistence(timeout: 10),
            "Expected the Discover Currencies leaderboard after tapping its tile"
        )
        XCTAssertTrue(
            app.buttons.matching(identifier: "discover-leaderboard-row").firstMatch
                .waitForExistence(timeout: 30),
            "Expected the leaderboard to list at least one currency"
        )
        XCTAssertFalse(
            app.buttons["discover-create-currency-card"].exists,
            "The promo card belongs to v1 — creation has its own Wallet tile now"
        )

        // MARK: Create a Currency → the creation summary.
        // Discover is a push onto the wallet's stack, so back out to the tab
        // root; the tab bar is hidden while the stack is non-empty.
        waitAndTap(app.navigationBars.buttons.firstMatch)
        assertMainScreenReached(timeout: 15, "Expected the Wallet root after leaving Discover")

        wallet.tapCreateCurrencyTile(from: self)
        XCTAssertTrue(
            app.navigationBars["Create Your Currency"].waitForExistence(timeout: 10),
            "Expected the Create Your Currency summary after tapping its tile"
        )
    }
}
