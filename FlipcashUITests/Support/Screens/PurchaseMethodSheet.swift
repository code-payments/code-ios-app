//
//  PurchaseMethodSheet.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the PurchaseMethodSheet shown when the user's USDF
/// reserve doesn't cover the entered buy amount. Lists Apple Pay (conditional
/// on the Coinbase onramp gate), Phantom, and Other Wallet, plus a Dismiss
/// row.
@MainActor
struct PurchaseMethodSheet {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    /// Apple Pay row. Label contains the U+F8FF "Pay" glyph; matched by
    /// "Debit Card with" prefix so it's robust to glyph-rendering differences.
    var applePayButton: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Debit Card with'")).firstMatch
    }

    /// Phantom row. The button's label is just "Phantom" since the inline
    /// icon is template-rendered and contributes no accessibility text.
    var phantomButton: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == 'Phantom'")).firstMatch
    }

    /// Other Wallet row.
    var otherWalletButton: XCUIElement {
        app.buttons["Other Wallet"]
    }

    /// Dismiss row at the bottom of the sheet.
    var dismissButton: XCUIElement {
        app.buttons["Dismiss"]
    }

    // MARK: - Assertions

    func assertReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            phantomButton.waitForExistence(timeout: timeout),
            "Expected PurchaseMethodSheet with the Phantom row"
        )
    }

    // MARK: - Actions

    func selectPhantom(from testCase: BaseUITestCase) {
        testCase.waitUntilHittableAndTap(phantomButton)
    }

    func selectOtherWallet(from testCase: BaseUITestCase) {
        testCase.waitUntilHittableAndTap(otherWalletButton)
    }
}
