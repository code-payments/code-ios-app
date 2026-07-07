//
//  GiveDiscoverGateRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression: tapping Cash while holding USDF but no community currency must
/// surface the "No Community Currencies Yet" dialog routing to Discover — not
/// the Add Money deposit prompt, and not the give amount entry. Cash is given
/// in community currencies; USDF alone can't be given, but with USDF on hand
/// the fix is buying a currency, not depositing more.
///
/// **Prerequisites:**
/// - `FLIPCASH_UI_TEST_USDF_ONLY_ACCESS_KEY` set in `secrets.local.xcconfig`
///   (the account holds USDF and no other currency).
final class GiveDiscoverGateRegressionTests: BaseUITestCase {

    override var requiresUsdfOnlyAccount: Bool { true }

    func testGiveWithUsdfOnly_routesToDiscover() {
        assertMainScreenReached()

        waitAndTap(app.buttons["Cash"])

        XCTAssertTrue(
            app.staticTexts["No Community Currencies Yet"].waitForExistence(timeout: 10),
            "Expected the Discover nudge when the account holds USDF but no community currency"
        )
        XCTAssertFalse(
            app.staticTexts["No Balance Yet"].exists,
            "A USDF-funded account must not be routed to the Add Money deposit prompt"
        )

        waitUntilHittableAndTap(app.buttons["Discover Currencies"])

        XCTAssertTrue(
            app.navigationBars["Discover Currencies"].waitForExistence(timeout: 10),
            "Expected the Discover sheet after tapping Discover Currencies"
        )
    }
}
