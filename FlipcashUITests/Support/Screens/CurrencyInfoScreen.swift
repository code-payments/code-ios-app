//
//  CurrencyInfoScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the CurrencyInfoScreen.
/// Provides access to the action tiles: Give / Convert / Withdraw for a held
/// currency, and Get for one the account doesn't hold yet.
@MainActor
struct CurrencyInfoUIScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    /// Only present for a currency the account doesn't hold yet.
    var getButton: XCUIElement { app.buttons["Get"] }
    var giveButton: XCUIElement { app.buttons["Give"] }
    var convertButton: XCUIElement { app.buttons["Convert"] }
    var withdrawButton: XCUIElement { app.buttons["Withdraw"] }
    var viewTransactionButton: XCUIElement { app.buttons["Transaction History"] }

    // MARK: - Assertions

    func assertReached(timeout: TimeInterval = 10) {
        // The back chevron is the one element present regardless of whether
        // the account holds this currency (the tiles differ by ownership).
        XCTAssertTrue(
            app.buttons["currency-info-back"].waitForExistence(timeout: timeout),
            "Expected to reach CurrencyInfoScreen"
        )
    }
}
