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
    var tab: XCUIElement { app.tabBars.buttons["Chat"].firstMatch }

    /// The tab's navigation-bar title — its presence means the list has
    /// rendered, whether or not the account has a conversation.
    var title: XCUIElement { app.staticTexts["Chat"] }

    /// The empty state, shown until the first tip conversation exists.
    var emptyState: XCUIElement { app.staticTexts["No Chats Yet"] }

    /// The conversation rows, tip DMs and groups alike, matched by their `chat-row-*` identifier —
    /// the list also holds the filter chips and the archived row, so a bare cell query lands on those.
    private var conversationRows: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'chat-row-'"))
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

    /// The first conversation's row button, once at least one exists. Waits
    /// because the conversations hydrate asynchronously after the tab opens.
    /// Returns `nil` when the account has no conversation — the caller skips.
    func firstConversationRow(timeout: TimeInterval = 15) -> XCUIElement? {
        let row = conversationRows.firstMatch
        return row.waitForExistence(timeout: timeout) ? row : nil
    }

    /// The first tip-DM row, skipping groups, which share the list but have no
    /// counterpart to open. Waits out the list's hydration, then
    /// returns `nil` when the account has no tip DM — the caller skips.
    func firstTipDMRow(timeout: TimeInterval = 15) -> XCUIElement? {
        let row = app.buttons.matching(identifier: "chat-row-tip-dm").firstMatch
        return row.waitForExistence(timeout: timeout) ? row : nil
    }
}
