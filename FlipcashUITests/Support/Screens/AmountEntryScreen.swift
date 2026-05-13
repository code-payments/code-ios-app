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

    /// The "Buy" `CodeButton` on the amount entry screen.
    /// When the BuyAmountScreen sheet is presented, there are two "Buy" buttons in
    /// the hierarchy — the footer button on CurrencyInfoScreen (index 0, behind the sheet)
    /// and the action button on the amount entry sheet (index 1, on top).
    var buyActionButton: XCUIElement {
        app.buttons.matching(identifier: "Buy").element(boundBy: 1)
    }

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

    /// Enters an amount near the per-transaction cap so the USDF gate routes
    /// to the funding picker regardless of the test account's USDF balance.
    /// The single-transaction limit is $1,000.00; entering "999" stays inside
    /// it while exceeding any plausible test-account reserve.
    func enterPickerTriggeringAmount() {
        XCTAssertTrue(keypadZero.waitForExistence(timeout: 5), "Expected keypad to be visible")

        keypadButton("9").tap()
        keypadButton("9").tap()
        keypadButton("9").tap()
    }
}
