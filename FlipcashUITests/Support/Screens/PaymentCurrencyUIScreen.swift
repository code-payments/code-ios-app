//
//  PaymentCurrencyUIScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the buy flow's Select Payment Currency step.
@MainActor
struct PaymentCurrencyUIScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    var title: XCUIElement { app.staticTexts["Select Payment Currency"] }

    /// The USDF payment row (always present, eligible unless underfunded).
    var usdfRow: XCUIElement { app.buttons["payment-currency-row-usdf"] }

    /// First non-USDF payment row. The buy target never appears in the list,
    /// and underfunded rows stay tappable (their Buy surfaces the Buy Maximum
    /// sheet).
    var firstTokenRow: XCUIElement { app.buttons.matching(identifier: "payment-currency-row").firstMatch }

    // MARK: - Assertions

    func assertReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            title.waitForExistence(timeout: timeout),
            "Expected the Select Payment Currency screen"
        )
    }
}
