//
//  ComposerClearSmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// Sending has to leave the composer empty. It sometimes did not: the sent text stayed in the
/// field, so the next message had to be erased before one could be written.
///
/// The failure is a race between the last keystroke and the send, not a property of any one
/// message, so a single send proves nothing either way. Each test sends a run of them and checks
/// the field after every one.
///
/// **Prerequisites:** the `FLIPCASH_UI_TEST_ACCESS_KEY` account needs at least one chat
/// conversation. With none, each test skips rather than fails.
@MainActor
final class ComposerClearSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    /// Sends per test. Enough runs at the race to make a real failure likely, few enough that the
    /// suite stays inside its time allowance — the sends are real, and each one reaches the server.
    private static let sendCount = 6

    private var conversation: ConversationUIScreen { ConversationUIScreen(app: app) }

    override func setUp() async throws {
        try await super.setUp()
        // A run of round-trip sends passes XCTest's 2-minute default.
        executionTimeAllowance = 600
    }

    /// The plain case: type, send, and the field is empty and ready for the next message.
    ///
    /// Delivery is deliberately not awaited between sends. What is under test is the composer's
    /// state the instant the send is dispatched, and waiting on a receipt would settle the very
    /// window the failure lives in.
    func testSendingMessages_leavesTheComposerEmptyEachTime() throws {
        try openConversation()

        for attempt in 1...Self.sendCount {
            let message = Self.uniqueText("clear \(attempt)")
            conversation.sendWithoutSettling(message, from: self)
            conversation.assertComposerCleared(of: message)
        }
    }

    /// The reply branch of the send, which empties the field through the same call while also
    /// taking the composer out of replying — a second state change landing on the same update.
    func testSendingAReply_leavesTheComposerEmpty() throws {
        try openConversation()

        let original = Self.uniqueText("original")
        conversation.sendMessage(original, from: self)
        conversation.assertMessageDelivered(original)

        let answer = Self.uniqueText("answer")
        conversation.beginReply(to: original, from: self)
        conversation.sendWithoutSettling(answer, from: self)
        conversation.assertComposerCleared(of: answer)
    }

    /// A draft written and sent in one go, with no pause anywhere in it. Typing the body in
    /// separate bursts leaves the field mid-edit when the send lands, which is the state the lost
    /// clear needs and the one a single `typeText` is least likely to produce on its own.
    func testSendingMidEdit_leavesTheComposerEmpty() throws {
        try openConversation()

        for attempt in 1...Self.sendCount {
            let message = Self.uniqueText("burst \(attempt)")
            waitUntilHittableAndTap(conversation.messageField)

            let send = conversation.composerSendButton
            for word in message.split(separator: " ") {
                conversation.messageField.typeText("\(word) ")
            }
            send.tap()

            conversation.assertComposerCleared(of: message)
        }
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
            throw XCTSkip("The test account has no chat conversation — skipping the composer suite")
        }
        row.tap()

        XCTAssertTrue(
            conversation.messageField.waitForExistence(timeout: 30),
            "Expected the conversation's composer. On screen: [\(visibleText())]"
        )
    }

    /// A per-run body, so a field query can never match text left behind by an earlier run.
    private static func uniqueText(_ prefix: String) -> String {
        "\(prefix) \(Int(Date().timeIntervalSince1970 * 1000) % 1_000_000)"
    }
}
