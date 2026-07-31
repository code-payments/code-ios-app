//
//  TipsUIScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the Tips sheet — the list of tip-DM conversations reached
/// from the ScanBottomBar's Tips tab (gated by the `enableTips` beta flag).
@MainActor
struct TipsUIScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    /// The Tips tab on the ScanBottomBar.
    var tab: XCUIElement { app.buttons["scan-tips-button"] }

    /// The always-present call to action at the top of the list — its presence
    /// means the Tips list has rendered.
    var tipcardButton: XCUIElement { app.buttons["show-my-tipcard-button"] }

    /// The Tips sheet's Close button.
    var closeButton: XCUIElement { app.navigationBars["Tips"].buttons["Close"] }

    /// The tip-conversation rows. The list's first cell is the "Show My Tipcard"
    /// row; every cell after it is a conversation, so the row buttons are the
    /// cells' buttons past index 0.
    private var conversationCells: [XCUIElement] {
        Array(app.cells.allElementsBoundByIndex.dropFirst())
    }

    // MARK: - Actions

    /// Opens the Tips sheet from the main screen and waits for the list to load.
    func open(from testCase: BaseUITestCase) {
        testCase.waitAndTap(tab)
        XCTAssertTrue(
            tipcardButton.waitForExistence(timeout: 30),
            "Expected the Tips list (the 'Show My Tipcard' button)"
        )
    }

    /// The first tip conversation's row button, once at least one exists. Polls
    /// because the conversations hydrate asynchronously after the sheet opens.
    /// Returns `nil` when the account has no tip DM — the caller skips.
    func firstConversationRow(timeout: TimeInterval = 15) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let cell = conversationCells.first {
                let button = cell.buttons.firstMatch
                if button.exists { return button }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nil
    }

    /// Closes the Tips sheet, returning to the main screen.
    func close(from testCase: BaseUITestCase) {
        testCase.waitAndTap(closeButton)
    }
}
