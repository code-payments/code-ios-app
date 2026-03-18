//
//  GiveSmokeTests.swift
//  FlipcashUITests
//

import XCTest

final class GiveSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testGiveFlow_showsBillWithSendAsLink() {
        // Main screen
        waitAndTap(app.buttons["Give"])

        // EnterAmountView — enter $0.01
        waitAndTap(app.buttons["0"])
        app.buttons["."].tap()
        app.buttons["0"].tap()
        app.buttons["1"].tap()

        waitAndTap(app.buttons["Next"])

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
