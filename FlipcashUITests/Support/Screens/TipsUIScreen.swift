//
//  TipsUIScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the Chat tab — the list of tip-DM conversations.
///
/// The tab-bar UI embeds this list as a tab rather than presenting it as a
/// sheet, so there is nothing to close, and `TipsScreen(isEmbedded: true)`
/// renders the conversations unconditionally: the tip-card intro and its inline
/// "Show My Tip Card" button are v1 only, and the tip card has its own tab.
@MainActor
struct TipsUIScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    /// The Chat tab on the tab bar.
    var tab: XCUIElement { app.buttons["Chat"] }

    /// The tab's large flush title — its presence means the list has rendered,
    /// whether or not the account has a conversation.
    var title: XCUIElement { app.staticTexts["Chats"] }

    /// The empty state, shown until the first tip conversation exists.
    var emptyState: XCUIElement { app.staticTexts["No Chats Yet"] }

    /// The tip-conversation rows. Every cell is a conversation — the v1 list's
    /// leading "Show My Tip Card" row is gone, so none is skipped.
    private var conversationCells: [XCUIElement] {
        app.cells.allElementsBoundByIndex
    }

    // MARK: - Actions

    /// Opens the Chat tab and waits for the list to load.
    func open(from testCase: BaseUITestCase) {
        testCase.waitAndTap(tab)
        XCTAssertTrue(
            title.waitForExistence(timeout: 30),
            "Expected the Chat tab's conversation list"
        )
    }

    /// The first tip conversation's row button, once at least one exists. Polls
    /// because the conversations hydrate asynchronously after the tab opens.
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
}
