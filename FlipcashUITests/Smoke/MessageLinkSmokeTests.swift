//
//  MessageLinkSmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// Opens a message link to a message older than the transcript's first page and checks the chat
/// pages back to it, lands on it and highlights it.
///
/// **Prerequisites:** the `FLIPCASH_UI_TEST_ACCESS_KEY` account (XCTests) has a tip DM with Brandon
/// McAnsh holding more than a page of history, so message `targetSeq` is outside the window a
/// fresh login loads. A link to a chat the account can't open fails the landing assertion.
@MainActor
final class MessageLinkSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    /// The XCTests ↔ Brandon McAnsh tip DM (contact DMs aren't link targets), as the base64url id a DM link carries.
    private static let chatID = "RiQXL4GQUX_EnpuDJs3kv4UORH3QvhQIfioz_QjAFbM"

    /// Far enough below the newest message that the first page doesn't hold it.
    private static let targetSeq = 100

    private var conversation: ConversationUIScreen { ConversationUIScreen(app: app) }

    /// The row a jump landed on; `ChatViewController` names it while it is the attention target.
    private var attentionTarget: XCUIElement {
        app.cells.matching(identifier: "chat-attention-target").firstMatch
    }

    override func setUp() async throws {
        try await super.setUp()
        // `app.open` relaunches the app when it isn't foremost, and a relaunch replays
        // `--ui-testing`, whose nuke logs the account out. Clear them so a relaunch resumes it.
        app.launchArguments = []
        // Paging back several pages over the network runs past XCTest's 2-minute default.
        executionTimeAllowance = 300
    }

    /// The link opens the chat, pages back to a message it hadn't loaded, and highlights it on
    /// screen rather than leaving the transcript at the bottom.
    func testMessageLink_toUnloadedMessage_landsAndHighlights() throws {
        assertMainScreenReached()

        app.open(URL(string: "flipcash://chat/\(Self.chatID)/m/\(Self.targetSeq)")!)

        XCTAssertTrue(
            conversation.messageField.waitForExistence(timeout: 30),
            "Expected the link to open the conversation. On screen: [\(visibleText())]"
        )
        XCTAssertTrue(
            attentionTarget.waitForExistence(timeout: 60),
            "Expected the transcript to land on and highlight message \(Self.targetSeq). On screen: [\(visibleText())]"
        )
        let onScreen = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: attentionTarget)
        XCTAssertEqual(
            XCTWaiter().wait(for: [onScreen], timeout: 10), .completed,
            "Expected the highlighted message on screen, not scrolled past. Target at \(attentionTarget.frame)"
        )
    }
}
