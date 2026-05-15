//
//  USDCDepositEducationScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the USDCDepositEducationScreen — the pre-flight shown
/// when the user picks "Other Wallet" from `PurchaseMethodSheet`. Explains
/// the USDC→USDF auto-conversion and hands off to the address screen via
/// the Next button.
@MainActor
struct USDCDepositEducationScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    var title: XCUIElement {
        app.staticTexts["Deposit USDC"]
    }

    var nextButton: XCUIElement {
        app.buttons["Next"]
    }

    // MARK: - Assertions

    func assertReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            title.waitForExistence(timeout: timeout),
            "Expected USDCDepositEducationScreen with 'Deposit USDC' title"
        )
    }

    // MARK: - Actions

    func tapNext(from testCase: BaseUITestCase) {
        testCase.waitUntilHittableAndTap(nextButton)
    }
}
