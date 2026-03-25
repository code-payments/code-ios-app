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

    /// The Phantom wallet button. Label includes "Solana USDC With, Phantom".
    var phantomButton: XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Phantom'")
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

    func selectPhantom(from testCase: BaseUITestCase) {
        testCase.waitAndTap(
            phantomButton,
            timeout: 10,
            "Expected Phantom option in funding sheet"
        )
    }
}
