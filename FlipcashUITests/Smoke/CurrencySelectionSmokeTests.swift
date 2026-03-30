//
//  CurrencySelectionSmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// Tests currency selection on a brand new (empty) account
/// to verify fiat exchange rates are available.
final class CurrencySelectionSmokeTests: BaseUITestCase {

    func testCurrencySelection_newAccount_changeCurrency_updatesFlag() {
        // Create a brand new empty account
        waitAndTap(app.buttons["Create a New Account"])
        waitAndTap(app.buttons["Wrote the 12 Words Down Instead?"])
        waitAndTap(app.buttons["Yes, I Wrote Them Down"])
        allowPushNotificationsIfNeeded()

        assertMainScreenReached()

        let wallet = WalletScreen(app: app)

        // Navigate to Wallet
        wallet.open(from: self)

        // Verify the balance header shows the US flag (locale forced to en_US)
        let usFlag = wallet.balanceHeader.images["flag-us"]
        XCTAssertTrue(
            usFlag.waitForExistence(timeout: 10),
            "Expected US flag in balance header for default USD currency"
        )

        // Tap the balance header to open currency selection
        wallet.tapBalanceHeader(from: self)

        // Verify the currency selection sheet appeared
        let searchField = app.searchFields["Search Regions"]
        XCTAssertTrue(
            searchField.waitForExistence(timeout: 10),
            "Expected currency selection search field"
        )

        // Search for Japanese Yen and select it
        waitUntilHittableAndTap(searchField, "Expected search field to be hittable after sheet animation")
        searchField.typeText("Japanese")

        let japaneseYen = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Japanese Yen'")
        ).firstMatch
        waitAndTap(japaneseYen)

        // After selection, the sheet dismisses and the flag should update to Japanese.
        // This assertion catches missing fiat exchange rates — without rates the
        // balance can't be converted and the flag won't change.
        let jpFlag = wallet.balanceHeader.images["flag-jp"]
        XCTAssertTrue(
            jpFlag.waitForExistence(timeout: 10),
            "Expected Japanese flag in balance header after selecting JPY — fiat exchange rates may be missing"
        )
    }
}
