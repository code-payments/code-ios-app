//
//  DepositRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression tests for the Deposit Funds flow.
final class DepositRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    // MARK: - Tests

    func testDepositFlow_viewAndCopyAddress() {
        let settings = SettingsUIScreen(app: app)

        assertMainScreenReached()

        // Navigate: Main → Settings → Deposit
        settings.open(from: self)
        waitAndTap(settings.depositButton)

        // Select the first currency
        let firstCurrency = app.cells.firstMatch
        XCTAssertTrue(
            firstCurrency.waitForExistence(timeout: 10),
            "Expected at least one currency in the deposit list"
        )
        firstCurrency.tap()

        // Tap "Copy Address" and verify button transitions to "Copied" success state
        let copyButton = app.buttons["Copy Address"]
        XCTAssertTrue(
            copyButton.waitForExistence(timeout: 10),
            "Expected DepositScreen with 'Copy Address' button"
        )
        copyButton.tap()

        // CodeButton transitions to .successText("Copied") which changes the button label.
        let copiedButton = app.buttons["Copied"]
        XCTAssertTrue(
            copiedButton.waitForExistence(timeout: 5),
            "Expected button to transition to 'Copied' state"
        )
    }
}
