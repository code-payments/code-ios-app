//
//  GiveSmokeTests.swift
//  FlipcashUITests
//

import XCTest

final class GiveSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testGiveFlow_showsBillWithSendAsLink() {
        assertMainScreenReached()

        let amountEntry = navigateToGiveAmount()

        // Enter $0.01 and proceed to bill
        amountEntry.enterMinimumAmount()
        waitAndTap(amountEntry.nextButton)

        // Bill should appear with "Send as a Link" button
        let sendAsLink = app.buttons["Send as a Link"]
        XCTAssertTrue(
            sendAsLink.waitForExistence(timeout: 30),
            "Expected the bill to appear with the 'Send as a Link' button"
        )

        // Dismiss the bill
        waitAndTap(app.buttons["Cancel"])

        // Should return to main screen
        assertMainScreenReached("Expected to return to the main screen after cancelling the bill")
    }
}
