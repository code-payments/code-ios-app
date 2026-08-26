//
//  AddMoneyStartScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the standalone Add Money flow: "No Balance Yet" →
/// "Add Money With" → the per-method screens.
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

    /// The "No Balance Yet" primary CTA, scoped to the dialog. An unscoped
    /// "Add Money" match can resolve to the wallet behind the dialog, which has
    /// both a tile and a new-user tutorial row under that label.
    var addMoneyButton: XCUIElement {
        app.otherElements["No Balance Yet"].buttons["Add Money"]
    }

    // MARK: - Add Money With

    /// The method picker's heading. The tab-bar UI titles it "Add Money With";
    /// "Select Method" was the pre-tab-bar heading.
    var methodPickerTitle: XCUIElement {
        app.staticTexts["Add Money With"]
    }

    /// Debit card (Coinbase) row, matched by identifier — the row carries the
    /// U+F8FF Apple glyph + "Pay" as its trailing icon, brittle to match by label.
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

    // MARK: - Assertions

    func assertNoBalanceReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            noBalanceTitle.waitForExistence(timeout: timeout),
            "Expected the Add Money flow to open on 'No Balance Yet'"
        )
    }

    func assertMethodPickerReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            methodPickerTitle.waitForExistence(timeout: timeout),
            "Expected the 'Add Money With' sheet"
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
