//
//  WithdrawRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression tests for the Withdraw Funds flow.
final class WithdrawRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    // MARK: - Tests

    func testWithdrawFlow_fullFlowToSummary() {
        let settings = SettingsUIScreen(app: app)
        let amountEntry = AmountEntryScreen(app: app)

        assertMainScreenReached()

        // Navigate: Main → Settings → Withdraw Funds → select first currency
        settings.open(from: self)
        waitAndTap(settings.withdrawFundsRow)

        let firstCurrency = app.cells.firstMatch
        XCTAssertTrue(
            firstCurrency.waitForExistence(timeout: 10),
            "Expected at least one currency in the withdraw list"
        )
        firstCurrency.tap()

        // Enter $0.01 and proceed to address entry
        amountEntry.enterMinimumAmount()
        waitAndTap(amountEntry.nextButton)

        // Enter a valid Solana address
        let addressField = app.textFields["Enter address"]
        XCTAssertTrue(
            addressField.waitForExistence(timeout: 10),
            "Expected address text field on WithdrawAddressScreen"
        )
        addressField.tap()
        addressField.typeText("35F7fV6RoL3kTSj5cddmLJqhjjnFeJW7tgNih7EyL9P8")

        // Wait for the server to validate the address ("Valid address" label appears)
        let validLabel = app.staticTexts["Valid address"]
        XCTAssertTrue(
            validLabel.waitForExistence(timeout: 15),
            "Expected server to validate the destination address"
        )

        // "Next" enables asynchronously after validation completes.
        // The button exists in the hierarchy but is disabled until canCompleteWithdrawal is true.
        // Use waitUntilHittableAndTap to wait for it to become enabled.
        waitUntilHittableAndTap(amountEntry.nextButton)

        // WithdrawSummaryScreen should show the "Withdraw" button and the destination address
        let withdrawButton = app.buttons["Withdraw"]
        XCTAssertTrue(
            withdrawButton.waitForExistence(timeout: 10),
            "Expected WithdrawSummaryScreen with 'Withdraw' button"
        )

        let addressText = app.staticTexts["35F7fV6RoL3kTSj5cddmLJqhjjnFeJW7tgNih7EyL9P8"]
        XCTAssertTrue(
            addressText.exists,
            "Expected destination address displayed on summary screen"
        )
    }
}
