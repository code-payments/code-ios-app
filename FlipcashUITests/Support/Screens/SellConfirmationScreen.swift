//
//  SellConfirmationScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the CurrencySellConfirmationScreen showing fee breakdown and final Sell button.
@MainActor
struct SellConfirmationScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    /// The "Sell" `CodeButton` on the confirmation screen.
    /// Index 0 is the CurrencyInfoScreen footer "Sell" button (behind the sheet);
    /// index 1 is the confirmation action button (on the sheet).
    var sellButton: XCUIElement {
        app.buttons.matching(identifier: "Sell").element(boundBy: 1)
    }

    // MARK: - Actions

    func confirmSell(from testCase: BaseUITestCase) {
        testCase.waitUntilHittableAndTap(sellButton, timeout: 10, "Expected Sell confirmation screen")
    }
}
