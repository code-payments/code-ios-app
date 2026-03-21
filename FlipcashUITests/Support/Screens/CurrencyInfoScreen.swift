//
//  CurrencyInfoScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the CurrencyInfoScreen.
/// Provides access to Buy, Sell, and Give actions in the floating footer.
@MainActor
struct CurrencyInfoUIScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    var buyButton: XCUIElement { app.buttons["Buy"] }
    var sellButton: XCUIElement { app.buttons["Sell"] }
    var giveButton: XCUIElement { app.buttons["Give"] }
    var viewTransactionButton: XCUIElement { app.buttons["View Transaction"] }

    // MARK: - Assertions

    func assertReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            buyButton.waitForExistence(timeout: timeout),
            "Expected to reach CurrencyInfoScreen with Buy button"
        )
    }
}
