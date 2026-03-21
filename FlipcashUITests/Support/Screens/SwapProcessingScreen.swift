//
//  SwapProcessingScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the SwapProcessingScreen shown during buy/sell transactions.
@MainActor
struct SwapProcessingUIScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    var okButton: XCUIElement { app.buttons["OK"] }

    // MARK: - Actions

    /// Waits for the swap to complete (up to 2 minutes) and taps OK.
    func waitForCompletionAndDismiss() {
        XCTAssertTrue(
            okButton.waitForExistence(timeout: 120),
            "Expected swap processing to complete within 2 minutes"
        )
        okButton.tap()
    }
}
