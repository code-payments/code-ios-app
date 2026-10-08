//
//  ProfileCardSmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// Covers the profile card the share sheet's Show Profile Card tile draws over the sheet, and its
/// Close button.
///
/// **Prerequisites:** the `FLIPCASH_UI_TEST_ACCESS_KEY` account needs a display
/// name — without one the tab has no Share button and no card to show.
@MainActor
final class ProfileCardSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    /// Share → Show Profile Card presents the card with its Download action, and Close uncovers the
    /// share sheet.
    func testShowProfileCard_opensAndCloses() throws {
        assertMainScreenReached()
        waitAndTap(app.tabBars.buttons["You"].firstMatch)
        waitAndTap(app.buttons["you-share"])
        waitAndTap(app.buttons["profile-card-tile"])

        let download = app.buttons["profile-card-download"]
        XCTAssertTrue(download.waitForExistence(timeout: 10), "Expected the profile card with its Download action")

        waitAndTap(app.buttons["profile-card-close"])

        // The card draws over the sheet, so the sheet's tiles stay in the tree while it is up; the
        // card's own Download leaving is what shows it closed.
        XCTAssertTrue(download.waitForNonExistence(timeout: 10), "Expected Close to remove the card")
        XCTAssertTrue(app.buttons["profile-card-tile"].isHittable, "Expected Close to land back on the share sheet")
    }
}
