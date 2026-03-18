//
//  GiveSmokeTests.swift
//  FlipcashUITests
//

import XCTest

final class GiveSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testGiveFlow_showsBillWithSendAsLink() {
        // Main screen — tap Give and wait for the amount entry keypad.
        // On CI the balance may not be fetched yet, showing "No Balance Yet".
        // If that happens, dismiss the dialog and retry up to 3 times,
        // giving the session ~30s total to fetch balances.
        let keypadZero = app.buttons["0"]
        for attempt in 1...3 {
            waitAndTap(app.buttons["Give"])
            if keypadZero.waitForExistence(timeout: 10) { break }

            // "No Balance Yet" dialog likely appeared — dismiss and retry
            let ok = app.buttons["OK"]
            if ok.exists { ok.tap() }
            XCTAssertFalse(attempt == 3, "Balance did not load after 3 attempts")
        }

        // EnterAmountView — enter $0.01
        keypadZero.tap()
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
