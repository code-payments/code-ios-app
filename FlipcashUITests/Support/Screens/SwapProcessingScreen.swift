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

    /// Waits for a submitted swap to finish on either path and leaves the flow dismissed.
    ///
    /// - Fast path: the confirm screen settles in place (button spins, then shows success)
    ///   and the flow dismisses without the processing screen ever appearing.
    /// - Slow path: the swap outlasts the 5s inline window, the processing screen is
    ///   pushed, and its OK button dismisses.
    ///
    /// - Parameter confirmAnchor: An element only the confirm screen shows (its
    ///   confirm button). Its absence with no processing screen means the flow dismissed.
    func waitForCompletionAndDismiss(confirmAnchor: XCUIElement, timeout: TimeInterval = 120) {
        let deadline = Date().addingTimeInterval(timeout)
        var goneChecks = 0

        while Date() < deadline {
            if okButton.exists {
                okButton.tap()
                return
            }

            // The push to the processing screen and the confirm screen leaving can land a
            // frame apart, so only a sustained absence of both counts as the fast path.
            if processingTitle.exists || confirmAnchor.exists {
                goneChecks = 0
            } else {
                goneChecks += 1
                if goneChecks >= 4 { return }
            }
            _ = okButton.waitForExistence(timeout: 0.5)
        }

        XCTFail("Expected the swap to finish (inline or via the processing screen) within \(Int(timeout))s")
    }
}
