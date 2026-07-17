//
//  BuyConfirmationUIScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the buy flow's summary (confirmation) step.
@MainActor
struct BuyConfirmationUIScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    /// The summary's Buy button, targeted by identifier so the CurrencyInfo
    /// footer's "Buy" (behind the sheet) can never shift the match.
    var buyButton: XCUIElement { app.buttons["buy-confirmation-buy"] }
    /// The You Pay block is a combined accessibility element ("You Pay: $X of
    /// <currency>"), so match by label prefix across element types.
    var youPayLabel: XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "You Pay"))
            .firstMatch
    }
    var exchangeFeeRow: XCUIElement { app.staticTexts["Exchange fee"] }

    // MARK: - Assertions

    func assertReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            youPayLabel.waitForExistence(timeout: timeout),
            "Expected the Buy summary screen"
        )
    }
}
