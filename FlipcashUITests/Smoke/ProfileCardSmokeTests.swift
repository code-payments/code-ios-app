//
//  ProfileCardSmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// Covers the profile card the You tab's Share menu shows over the tab, and its Close button.
///
/// **Prerequisites:** the `FLIPCASH_UI_TEST_ACCESS_KEY` account needs a display
/// name — without one the tab has no Share menu and no card to show.
@MainActor
final class ProfileCardSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    /// Share → Show Profile Card presents the card with its Download action, and Close returns.
    func testShowProfileCard_opensAndCloses() throws {
        assertMainScreenReached()
        waitAndTap(app.tabBars.buttons["You"].firstMatch)
        waitAndTap(app.buttons["you-share"])
        waitAndTap(app.buttons["Show Profile Card"])

        XCTAssertTrue(
            app.buttons["you-download-button"].waitForExistence(timeout: 10),
            "Expected the profile card with its Download action"
        )

        waitAndTap(app.buttons["profile-card-close"])

        // The card draws over the tab, so the tab's own buttons stay in the tree while it is up. The
        // toolbar button reads Settings again only once the card is gone.
        XCTAssertTrue(
            app.buttons["you-settings"].waitForExistence(timeout: 10),
            "Expected Close to return to the You tab, with the gear back in place of Download"
        )
    }
}
