//
//  DiscoverCurrenciesSmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// Tests the Discover top-level sheet entry from the Scan screen and verifies
/// the Create-Your-Own-Currency promo card pushes the creation summary screen.
final class DiscoverCurrenciesSmokeTests: BaseUITestCase {

    func testDiscover_newAccount_tapPromoCard_opensCurrencyCreation() {
        // Create a brand new empty account so this test runs without a UITest access key.
        waitAndTap(app.buttons["Create a New Account"])
        waitAndTap(app.buttons["Wrote the 12 Words Down Instead?"])
        waitAndTap(app.buttons["Yes, I Wrote Them Down"])
        allowPushNotificationsIfNeeded()

        assertMainScreenReached()

        // Tap the new Discover tab on the scan screen.
        let discoverButton = app.buttons["scan-discover-button"]
        waitAndTap(discoverButton, "Expected Discover tab on scan screen")

        // The Discover sheet should appear with the matching navigation title.
        let title = app.navigationBars["Discover Currencies"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 10),
            "Expected 'Discover Currencies' sheet to appear after tapping the Discover tab"
        )

        // Tap the promo card to navigate to the currency creation summary.
        let promoCard = app.buttons["discover-create-currency-card"]
        waitUntilHittableAndTap(promoCard, "Expected Create-Your-Own-Currency promo card to be hittable")

        // Verify the creation summary screen is reached.
        let creationTitle = app.navigationBars["Create Your Currency"]
        XCTAssertTrue(
            creationTitle.waitForExistence(timeout: 10),
            "Expected 'Create Your Currency' summary screen after tapping the promo card"
        )
    }
}
