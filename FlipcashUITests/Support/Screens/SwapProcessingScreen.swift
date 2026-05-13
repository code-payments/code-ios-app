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

    /// Static title rendered during the processing state ("This Will Take a Minute").
    /// Useful as a stable anchor while the swap is in-flight — the success/failed
    /// states swap it for "Transaction Complete" / "Something Went Wrong".
    var processingTitle: XCUIElement { app.staticTexts["This Will Take a Minute"] }

    // MARK: - Actions

    /// Waits for the processing screen to become visible.
    func assertReached(timeout: TimeInterval = 30) {
        XCTAssertTrue(
            processingTitle.waitForExistence(timeout: timeout),
            "Expected processing screen to be visible within \(timeout)s"
        )
    }

    /// Waits for the swap to complete (up to 2 minutes) and taps OK.
    func waitForCompletionAndDismiss() {
        XCTAssertTrue(
            okButton.waitForExistence(timeout: 120),
            "Expected swap processing to complete within 2 minutes"
        )
        okButton.tap()
    }
}
