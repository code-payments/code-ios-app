//
//  TransactionDetailsUIScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for `TransactionDetailsScreen` — the screen a tapped activity
/// row pushes from the per-token history.
///
/// Cancelling a pending cash link is the bar's trailing "Cancel" action, which
/// confirms through a "Cancel … Transfer?" dialog rather than acting directly.
@MainActor
struct TransactionDetailsUIScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    /// The screen's inline navigation title.
    var navigationBar: XCUIElement { app.navigationBars["Details"] }

    /// The bar's trailing Cancel action, present only while the activity can
    /// still be cancelled.
    var cancelButton: XCUIElement { navigationBar.buttons["Cancel"] }

    /// The destructive confirmation in the "Cancel … Transfer?" dialog.
    var cancelTransferButton: XCUIElement { app.buttons["Cancel Transfer"] }

    // MARK: - Actions

    /// Cancels the shown transfer: taps the bar's Cancel action, then confirms
    /// the dialog.
    func cancelTransfer(from testCase: BaseUITestCase) {
        testCase.waitAndTap(
            cancelButton,
            timeout: 10,
            "Expected the Details screen's Cancel action for a pending cash link"
        )
        testCase.waitAndTap(
            cancelTransferButton,
            timeout: 5,
            "Expected 'Cancel Transfer' confirmation dialog"
        )
    }

    // MARK: - Assertions

    /// Asserts the details screen was pushed.
    func assertReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            navigationBar.waitForExistence(timeout: timeout),
            "Expected the transaction Details screen (navigation title 'Details')"
        )
    }
}
