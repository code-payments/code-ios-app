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

    /// The name on the DM the sending suites post in: the XCTests account's tip DM with Brandon McAnsh.
    /// The account's groups can be public, so a send anywhere else (bar the "XCTest Bed" group)
    /// reaches real people.
    static let sendTargetName = "Brandon McAnsh"

    // MARK: - Actions

    /// Opens the Chat tab and waits for the list to load.
    func open(from testCase: BaseUITestCase) {
        testCase.waitAndTap(tab)
        XCTAssertTrue(
            title.waitForExistence(timeout: 30),
            "Expected the Chat tab's conversation list"
        )
    }

    /// The row of the tip DM with `sendTargetName`, the only conversation a suite may send into.
    /// Waits out the list's hydration, then returns `nil` when that DM is missing — the caller
    /// skips, and never falls back to another chat.
    func sendTargetDMRow(timeout: TimeInterval = 15) -> XCUIElement? {
        let row = app.buttons.matching(NSPredicate(
            format: "identifier == 'chat-row-tip-dm' AND label BEGINSWITH %@",
            Self.sendTargetName
        )).firstMatch
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
