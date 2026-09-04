//
//  ChatReplySmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// Drives replying to a chat message end to end: both entry points (the context menu and the
/// leading swipe), the composer strip that names the target, dismissing it without losing the
/// draft, and the quote panel the sent bubble carries.
///
/// Every message is one the test account sends into an existing DM, so the suite needs no second
/// device — a message you sent carries `.reply` like any other.
///
/// **Prerequisites:** the `FLIPCASH_UI_TEST_ACCESS_KEY` account needs at least one chat
/// conversation. With none, each test skips rather than fails.
///
/// **Not covered here:** the anchor move behind "tap a quote to jump to the original". Proving it
/// needs the original far enough off-screen that a jump is observable, which costs a dozen network
/// sends per run. `MessageLoaderRevealTests` covers the reveal itself; this suite checks the panel
/// is tappable and that tapping it leaves the transcript intact.
@MainActor
final class ChatReplySmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    private var conversation: ConversationUIScreen { ConversationUIScreen(app: app) }

    override func setUp() async throws {
        try await super.setUp()
        // Several round-trip sends per test run past XCTest's 2-minute default.
        executionTimeAllowance = 600
    }

    /// Long-pressing a sent message offers Reply, and choosing it opens the composer on that
    /// message — the strip naming what is being answered.
    func testMessageMenu_offersReplyAndAimsTheComposer() throws {
        try openConversation()

        let original = Self.uniqueText("original")
        conversation.sendMessage(original, from: self)
        conversation.assertMessageDelivered(original)

        conversation.beginReply(to: original, from: self)
    }

    /// Swiping a row towards the trailing edge is the same entry as the menu's Reply, without the
    /// menu — the gesture's own coexistence with scrolling and the long-press lift is what makes
    /// this worth driving on a real transcript.
    func testSwipingARow_opensTheReplyStrip() throws {
        try openConversation()

        let original = Self.uniqueText("swiped")
        conversation.sendMessage(original, from: self)
        conversation.assertMessageDelivered(original)

        conversation.swipeToReply(on: original, from: self)
        conversation.assertReplyStripQuotes(original)
    }

    /// The strip's ⊗ takes back the target and leaves the draft alone — a reply abandoned
    /// mid-sentence must not also lose the sentence.
    func testCancellingAReply_keepsTheDraft() throws {
        try openConversation()

        let original = Self.uniqueText("kept")
        conversation.sendMessage(original, from: self)
        conversation.assertMessageDelivered(original)

        conversation.beginReply(to: original, from: self)

        let draft = "half a thought"
        waitUntilHittableAndTap(conversation.messageField)
        conversation.messageField.typeText(draft)

        waitAndTap(conversation.cancelReplyButton)
        conversation.assertNoReplyStrip()

        let value = conversation.messageField.value as? String ?? ""
        XCTAssertTrue(
            value.contains(draft),
            "Expected the draft to survive dismissing the reply, got '\(value)'"
        )
        XCTAssertTrue(
            conversation.composerSendButton.exists,
            "Expected the send button to stay up — there is still text to send"
        )
    }

    /// A sent reply lands as an ordinary delivered message whose bubble embeds the original it
    /// answers, and the composer returns to writing a new message.
    func testSendingAReply_quotesTheOriginalAndClearsTheStrip() throws {
        try openConversation()

        let original = Self.uniqueText("quoted")
        conversation.sendMessage(original, from: self)
        conversation.assertMessageDelivered(original)

        let answer = Self.uniqueText("answer")
        conversation.sendReply(answer, to: original, from: self)

        conversation.assertNoReplyStrip(timeout: 15)
        conversation.assertMessageDelivered(answer)
        conversation.assertBubbleQuotes(original)
    }

    /// The quote panel inside a reply is a button, and pressing it leaves the transcript on the
    /// conversation with both rows still rendered — the jump's landing, not its paging.
    func testTappingAQuote_staysOnTheOriginal() throws {
        try openConversation()

        let original = Self.uniqueText("target")
        conversation.sendMessage(original, from: self)
        conversation.assertMessageDelivered(original)

        let answer = Self.uniqueText("pointer")
        conversation.sendReply(answer, to: original, from: self)
        conversation.assertBubbleQuotes(original)

        let panel = conversation.quotePanels.allElementsBoundByIndex.first { $0.label.contains(original) }
        let quote = try XCTUnwrap(panel, "Expected the reply's quote panel")
        waitUntilHittableAndTap(quote)

        XCTAssertTrue(
            conversation.messageBubble(original).waitForExistence(timeout: 15),
            "Expected the quoted original on screen after tapping its quote"
        )
        XCTAssertTrue(
            conversation.messageField.exists,
            "Expected to stay in the conversation after the jump"
        )
    }

    // MARK: - Helpers

    /// Opens the account's first chat, skipping the test when it has none — the suite drives an
    /// existing conversation rather than creating one, so an empty list is a missing fixture and
    /// not a defect.
    private func openConversation() throws {
        assertMainScreenReached()

        let chats = TipsUIScreen(app: app)
        chats.open(from: self)

        guard let row = chats.firstConversationRow(timeout: 30) else {
            throw XCTSkip("The test account has no chat conversation — skipping the reply suite")
        }
        row.tap()

        XCTAssertTrue(
            conversation.messageField.waitForExistence(timeout: 30),
            "Expected the conversation's composer. On screen: [\(visibleText())]"
        )
    }

    /// A per-run body, so a bubble query can never match a message left behind by an earlier run.
    private static func uniqueText(_ prefix: String) -> String {
        "\(prefix) \(Int(Date().timeIntervalSince1970 * 1000) % 1_000_000)"
    }
}
