//
//  TipsUIScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the Chat tab — the list of tip-DM conversations.
///
/// The tab hosts this list rather than presenting it as a sheet, so there is
/// nothing to close, and `TipsScreen(isEmbedded: true)` renders the
/// conversations unconditionally — the tip-card intro belongs to the sheet that
/// asks for a profile, and the tip card has its own tab.
@MainActor
struct TipsUIScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    /// The Chat tab on the tab bar.
    var tab: XCUIElement { app.buttons["Chat"] }

    /// The tab's navigation-bar title — its presence means the list has
    /// rendered, whether or not the account has a conversation.
    var title: XCUIElement { app.staticTexts["Chats"] }

    /// The empty state, shown until the first tip conversation exists.
    var emptyState: XCUIElement { app.staticTexts["No Chats Yet"] }

    /// The conversation rows, tip DMs and groups alike. Every cell is a conversation — there is no
    /// leading call-to-action row to skip.
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

    /// The first tip-DM row, skipping groups, which share the list but have no
    /// counterpart to open. Waits out the list's hydration, then
    /// returns `nil` when the account has no tip DM — the caller skips.
    func firstTipDMRow(timeout: TimeInterval = 15) -> XCUIElement? {
        let row = app.buttons.matching(identifier: "chat-row-tip-dm").firstMatch
        return row.waitForExistence(timeout: timeout) ? row : nil
    }
}
