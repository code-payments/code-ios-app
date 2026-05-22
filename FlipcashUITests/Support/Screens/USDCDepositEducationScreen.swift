//
//  USDCDepositEducationScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for `USDCDepositEducationScreen`: the USDC → USDF education
/// pre-flight. Exposes the Next CTA and the optional "Deposit Other Flipcash
/// Currencies" escape hatch.
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

    var depositOtherCurrenciesButton: XCUIElement {
        app.buttons["Deposit Other Flipcash Currencies"]
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

    func tapDepositOtherCurrencies(from testCase: BaseUITestCase) {
        testCase.waitAndTap(depositOtherCurrenciesButton)
    }
}
