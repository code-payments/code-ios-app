//
//  TipCardFullScreenSmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// Covers the You tab's full-screen tip card and the pull that puts it back:
/// up closes it, down does not.
///
/// **Prerequisites:** the `FLIPCASH_UI_TEST_ACCESS_KEY` account needs a display
/// name — without one the tab shows the add-your-name invitation and there is
/// no card to expand.
@MainActor
final class TipCardFullScreenSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    /// Pulling the expanded card up toward its slot puts it back, no close tap.
    func testExpandedTipCard_pullUp_collapses() throws {
        let closeButton = expandTipCard()

        pullCard(from: 0.6, to: 0.25)

        XCTAssertTrue(
            closeButton.waitForNonExistence(timeout: 10),
            "Expected the pull up to put the card back"
        )
    }

    /// Down is where expanding already took the card, so a downward pull is
    /// resisted rather than read as a dismissal.
    func testExpandedTipCard_pullDown_staysExpanded() throws {
        let closeButton = expandTipCard()

        pullCard(from: 0.4, to: 0.75)

        XCTAssertTrue(closeButton.exists, "Expected the card to stay expanded")
    }

    // MARK: - Helpers -

    /// Opens the card full screen and returns its close control.
    private func expandTipCard() -> XCUIElement {
        assertMainScreenReached()
        waitAndTap(app.buttons["You"])
        waitAndTap(app.buttons["you-fullscreen-button"])

        let closeButton = app.buttons["you-close-fullscreen-button"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 10), "Expected the card to expand")
        return closeButton
    }

    /// Drags the middle of the screen between two normalized heights — where
    /// the expanded card is, and slowly enough that only the distance counts,
    /// never a flick's projection.
    private func pullCard(from start: CGFloat, to end: CGFloat) {
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: start))
        let destination = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: end))
        origin.press(forDuration: 0.2, thenDragTo: destination)
    }
}
