//
//  AddMoneyStartScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the standalone Add Money flow: "No Balance Yet" →
/// "Select Method" → the per-method screens.
@MainActor
struct AddMoneyStartScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - No Balance Yet

    var noBalanceTitle: XCUIElement {
        app.staticTexts["No Balance Yet"]
    }

    /// The "No Balance Yet" primary CTA.
    var addMoneyButton: XCUIElement {
        app.buttons["Add Money"].firstMatch
    }

    // MARK: - Select Method

    var selectMethodTitle: XCUIElement {
        app.staticTexts["Select Method"]
    }

    /// Coinbase row, matched by identifier — the visible label is the U+F8FF
    /// Apple glyph + "Pay", brittle to match by label predicate.
    var payDebitCardButton: XCUIElement {
        app.buttons["apple-pay-method-button"]
    }

    var phantomButton: XCUIElement {
        app.buttons["phantom-method-button"]
    }

    var otherWalletButton: XCUIElement {
        app.buttons["other-wallet-method-button"]
    }

    // MARK: - Phantom education

    var phantomEducationTitle: XCUIElement {
        app.staticTexts["Add Money With Phantom"]
    }

    var connectPhantomButton: XCUIElement {
        app.buttons["Connect Your Phantom Wallet"]
    }

    // MARK: - Amount to Add

    var amountToAddNavBar: XCUIElement {
        app.navigationBars["Amount to Add"]
    }

    /// The action button on the "Amount to Add" screen. The "No Balance Yet"
    /// dialog is gone before this screen exists, so "Add Money" is unambiguous.
    var amountToAddActionButton: XCUIElement {
        app.buttons["Add Money"].firstMatch
    }

    // MARK: - Assertions

    func assertNoBalanceReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            noBalanceTitle.waitForExistence(timeout: timeout),
            "Expected the Add Money flow to open on 'No Balance Yet'"
        )
    }

    func assertSelectMethodReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            selectMethodTitle.waitForExistence(timeout: timeout),
            "Expected the 'Select Method' sheet"
        )
    }

    func assertAmountToAddReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            amountToAddNavBar.waitForExistence(timeout: timeout),
            "Expected the 'Amount to Add' screen"
        )
    }

    func assertPhantomEducationReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            phantomEducationTitle.waitForExistence(timeout: timeout),
            "Expected the 'Add Money With Phantom' education screen"
        )
        XCTAssertTrue(
            connectPhantomButton.exists,
            "Expected the 'Connect Your Phantom Wallet' CTA"
        )
    }

    // MARK: - Actions

    func tapAddMoney(from testCase: BaseUITestCase) {
        testCase.waitUntilHittableAndTap(addMoneyButton)
    }

    func selectPayDebitCard(from testCase: BaseUITestCase) {
        testCase.waitUntilHittableAndTap(payDebitCardButton)
    }

    func selectPhantom(from testCase: BaseUITestCase) {
        testCase.waitUntilHittableAndTap(phantomButton)
    }

    func selectOtherWallet(from testCase: BaseUITestCase) {
        testCase.waitUntilHittableAndTap(otherWalletButton)
    }
}
