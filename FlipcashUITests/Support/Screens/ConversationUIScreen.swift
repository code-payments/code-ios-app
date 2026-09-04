//
//  ConversationUIScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for a DM conversation. Drives Send Cash, the message composer,
/// the delivery receipts, and the reply affordances (menu, swipe, quote panel).
@MainActor
struct ConversationUIScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    var sendCashButton: XCUIElement { app.buttons["send-cash-button"] }
    var messageField: XCUIElement { app.textFields["Message"] }

    /// The composer's send arrow. A dedicated identifier avoids the same-labelled
    /// back button and ScanBottomBar "Send".
    var composerSendButton: XCUIElement { app.buttons["send-message-button"] }

    var deliveredReceipt: XCUIElement { app.staticTexts["Delivered"] }

    func messageBubble(_ text: String) -> XCUIElement { app.staticTexts[text] }

    // MARK: - Reply elements

    /// The quoted original above the composer, present only while a reply is open.
    var replyStrip: XCUIElement { app.otherElements["composer-reply-strip"] }

    /// The strip's quote text, combined into one element so VoiceOver reads it as a citation.
    var replyStripQuote: XCUIElement { app.otherElements["composer-reply-quote"] }

    /// The strip's dismiss control — takes back the target, not the draft.
    var cancelReplyButton: XCUIElement { app.buttons["cancel-reply-button"] }

    /// The context menu's Reply row. Scoped to `firstMatch` because the menu is hosted in a
    /// platter whose container type has moved between iOS versions.
    var replyMenuItem: XCUIElement { app.buttons["Reply"].firstMatch }

    /// The quote panels drawn inside sent reply bubbles.
    var quotePanels: XCUIElementQuery {
        app.buttons.matching(identifier: "chat-quote-panel")
    }

    // MARK: - Actions

    /// Opens the Send amount sheet on top of the conversation.
    func tapSendCash(from testCase: BaseUITestCase) {
        testCase.waitAndTap(sendCashButton)
    }

    /// Focuses the always-visible composer, types `text`, and sends it.
    func sendMessage(_ text: String, from testCase: BaseUITestCase) {
        testCase.waitUntilHittableAndTap(messageField)
        messageField.typeText(text)
        testCase.waitAndTap(composerSendButton)
    }

    // MARK: - Reply actions

    /// Long-presses `text`'s bubble and waits for its context menu.
    ///
    /// The press is delivered through `press(forDuration:)` rather than a tap so the transcript's
    /// long-press recognizer fires; `pressForDuration` shorter than ~1s lands as a tap on some
    /// hosts, which selects nothing and leaves no menu.
    func openMenu(on text: String, from testCase: BaseUITestCase) {
        let bubble = messageBubble(text)
        XCTAssertTrue(
            bubble.waitForExistence(timeout: 30),
            "Expected '\(text)' in the transcript before opening its menu"
        )
        testCase.waitForStableFrame(bubble)
        bubble.press(forDuration: 1.2)
    }

    /// Opens `text`'s menu and taps Reply, leaving the composer aimed at that message.
    func beginReply(to text: String, from testCase: BaseUITestCase) {
        openMenu(on: text, from: testCase)
        testCase.waitAndTap(replyMenuItem, timeout: 15, "Expected a Reply row in the message menu")
        assertReplyStripQuotes(text)
    }

    /// Swipes `text`'s bubble towards the leading edge, the gesture shortcut for Reply.
    func swipeToReply(on text: String, from testCase: BaseUITestCase) {
        let bubble = messageBubble(text)
        XCTAssertTrue(
            bubble.waitForExistence(timeout: 30),
            "Expected '\(text)' in the transcript before swiping it"
        )
        testCase.waitForStableFrame(bubble)
        bubble.swipeLeft()
    }

    /// Aims the composer at `original` through the menu, then sends `reply` as an answer to it.
    func sendReply(_ reply: String, to original: String, from testCase: BaseUITestCase) {
        beginReply(to: original, from: testCase)
        testCase.waitUntilHittableAndTap(messageField)
        messageField.typeText(reply)
        testCase.waitAndTap(composerSendButton)
    }

    // MARK: - Assertions

    /// Asserts the cash payment is marked "Delivered".
    func assertCashDelivered(timeout: TimeInterval = 40) {
        XCTAssertTrue(
            deliveredReceipt.waitForExistence(timeout: timeout),
            "Expected the cash payment to be marked 'Delivered'"
        )
    }

    /// Asserts `text`'s bubble appears and is marked "Delivered". The receipt
    /// rides the latest sent message, so one at/below the bubble is the message's,
    /// not the cash's.
    func assertMessageDelivered(_ text: String, timeout: TimeInterval = 30) {
        let bubble = messageBubble(text)
        XCTAssertTrue(
            bubble.waitForExistence(timeout: 15),
            "Expected the sent message to appear as a bubble in the transcript"
        )
        XCTAssertTrue(
            waitForReceipt(atOrBelow: bubble, timeout: timeout),
            "Expected the message to be marked 'Delivered'"
        )
    }

    /// Asserts the composer is open on a reply whose strip cites `text`.
    func assertReplyStripQuotes(_ text: String, timeout: TimeInterval = 15) {
        XCTAssertTrue(
            replyStrip.waitForExistence(timeout: timeout),
            "Expected the composer's reply strip after choosing Reply"
        )
        XCTAssertTrue(
            replyStripQuote.label.contains(text),
            "Expected the strip to cite '\(text)', got '\(replyStripQuote.label)'"
        )
    }

    /// Asserts no reply is open on the composer.
    func assertNoReplyStrip(timeout: TimeInterval = 5) {
        let gone = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: gone, object: replyStrip)
        XCTAssertEqual(
            XCTWaiter().wait(for: [expectation], timeout: timeout), .completed,
            "Expected the reply strip to be dismissed"
        )
    }

    /// Asserts a sent bubble carries a quote panel citing `original`.
    ///
    /// Scans every panel rather than resolving one: a transcript may hold earlier replies, and a
    /// single-element query over several matches raises "multiple matching elements".
    func assertBubbleQuotes(_ original: String, timeout: TimeInterval = 30) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if quotePanels.allElementsBoundByIndex.contains(where: { $0.label.contains(original) }) {
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTFail("Expected a reply bubble quoting '\(original)'. On screen: [\(app.staticTexts.allElementsBoundByIndex.prefix(15).map(\.label).joined(separator: " | "))]")
    }

    // MARK: - Helpers

    /// Polls until a "Delivered" receipt sits at or below `reference`'s top edge.
    /// Two "Delivered" labels can briefly coexist during the cash→message receipt
    /// hand-off (the transcript cross-fades), so scan all matches rather than
    /// resolving a single element — which raises "multiple matching elements".
    private func waitForReceipt(atOrBelow reference: XCUIElement, timeout: TimeInterval) -> Bool {
        let receipts = app.staticTexts.matching(NSPredicate(format: "label == %@", "Delivered"))
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let top = reference.frame.minY
            if receipts.allElementsBoundByIndex.contains(where: { $0.frame.minY >= top }) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }
}
