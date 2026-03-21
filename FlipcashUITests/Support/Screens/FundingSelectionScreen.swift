//
//  FundingSelectionScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the FundingSelectionSheet that appears when buying a currency.
@MainActor
struct FundingSelectionScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    /// The USDF reserves button. Title is dynamic ("USDF ($X.XX)"), matched by prefix.
    var usdfReservesButton: XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'USDF'")
        ).firstMatch
    }

    // MARK: - Actions

    func selectUSDF(from testCase: BaseUITestCase) {
        testCase.waitAndTap(
            usdfReservesButton,
            timeout: 10,
            "Expected USDF reserves option in funding sheet"
        )
    }
}
