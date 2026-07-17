//
//  AmountEntryScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the EnterAmountView keypad, shared across Give, Buy, and Sell flows.
@MainActor
struct AmountEntryScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    var keypadZero: XCUIElement { app.buttons["0"] }
    var keypadDecimal: XCUIElement { app.buttons["."] }
    var nextButton: XCUIElement { app.buttons["Next"] }

    func keypadButton(_ digit: String) -> XCUIElement { app.buttons[digit] }

    // MARK: - Actions

    /// Enters $0.01 using the on-screen keypad.
    func enterMinimumAmount() {
        XCTAssertTrue(keypadZero.waitForExistence(timeout: 5), "Expected keypad to be visible")

        keypadZero.tap()
        keypadDecimal.tap()
        keypadButton("0").tap()
        keypadButton("1").tap()
    }
}
