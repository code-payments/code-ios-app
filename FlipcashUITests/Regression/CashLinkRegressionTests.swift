//
//  CashLinkRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the cash link lifecycle: create a cash link, confirm it was "sent",
/// then navigate to transaction history and cancel it.
///
/// **Prerequisites:**
/// - A valid `FLIPCASH_UI_TEST_ACCESS_KEY` set in `secrets.local.xcconfig`
/// - The test account must have sufficient balance to give $0.01
///
/// **Why not claim via deeplink?**
/// Reading the cash link URL from the pasteboard triggers iOS's "Paste from Other Apps"
/// permission dialog on the XCUITest runner. This permission cannot be pre-granted or reset
/// via `simctl privacy`, making pasteboard-based tests unreliable on CI.
final class CashLinkRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testCashLink_createAndCancel() {
        let wallet = WalletScreen(app: app)
        let currencyInfo = CurrencyInfoUIScreen(app: app)

        assertMainScreenReached()

        // Step 1: Create a cash link via the Give flow.
        let amountEntry = navigateToGiveAmount()
        amountEntry.enterMinimumAmount()
        waitAndTap(amountEntry.nextButton)

        // Bill should appear — tap "Send as a Link" to create the cash link.
        let sendAsLink = app.buttons["Send as a Link"]
        XCTAssertTrue(
            sendAsLink.waitForExistence(timeout: 30),
            "Expected the bill to appear with the 'Send as a Link' button"
        )
        sendAsLink.tap()

        // Share sheet appears — tap "Copy" to dismiss it via a completed action.
        let copyButton = app.cells["Copy"]
        XCTAssertTrue(
            copyButton.waitForExistence(timeout: 10),
            "Expected the share sheet to appear with a 'Copy' action"
        )
        copyButton.tap()

        // "Did You Send The Link?" confirmation — tap "Yes"
        waitAndTap(app.buttons["Yes"], timeout: 10, "Expected 'Did You Send The Link?' confirmation")

        // Back on main screen
        assertMainScreenReached(timeout: 10, "Expected to return to main screen after sending cash link")

        // Step 2: Navigate to the pending cash link via transaction history.
        wallet.open(from: self)
        wallet.selectFirstCurrency()

        // CurrencyInfoScreen — tap "View Transaction" to open history
        waitAndTap(
            currencyInfo.viewTransactionButton,
            timeout: 10,
            "Expected 'View Transaction' button on CurrencyInfoScreen"
        )

        // Step 3: Tap the first "Sending" row to trigger the cancel dialog.
        // Rows are List cells containing "Sending" as a static text label.
        // There may be multiple pending cash links — tap the most recent (first) one.
        let sendingLabel = app.staticTexts.matching(identifier: "Sending").firstMatch
        XCTAssertTrue(
            sendingLabel.waitForExistence(timeout: 10),
            "Expected a 'Sending' transaction in history"
        )
        sendingLabel.tap()

        // Step 4: Confirm cancellation.
        let cancelTransfer = app.buttons["Cancel Transfer"]
        XCTAssertTrue(
            cancelTransfer.waitForExistence(timeout: 5),
            "Expected 'Cancel Transfer' confirmation dialog"
        )
        cancelTransfer.tap()
    }
}
