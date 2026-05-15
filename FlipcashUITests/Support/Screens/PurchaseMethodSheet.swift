//
//  PurchaseMethodSheet.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the PurchaseMethodSheet shown when the user's USDF
/// reserve doesn't cover the entered buy amount (or any time the launch flow
/// opens the picker). Lists Apple Pay (conditional on the Coinbase onramp
/// gate), Phantom, and Other Wallet (omitted for the launch flow), plus a
/// Dismiss row.
@MainActor
struct PurchaseMethodSheet {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    /// Apple Pay row. Matched by accessibility identifier — the visible label
    /// is just the U+F8FF Apple logo glyph + "Pay" (intentional per HIG),
    /// which is brittle to match by label predicate.
    var applePayButton: XCUIElement {
        app.buttons["apple-pay-method-button"]
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
