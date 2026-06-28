//
//  ConversationUIScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for a DM conversation. Drives Send Cash, the message composer,
/// and the delivery receipts.
@MainActor
struct ConversationUIScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    var sendCashButton: XCUIElement { app.buttons["Send Cash"] }
    var sendMessageButton: XCUIElement { app.buttons["Send Message"] }
    var messageField: XCUIElement { app.textFields["Message"] }

    /// The composer's send arrow. A dedicated identifier avoids the same-labelled
    /// back button and ScanBottomBar "Send".
    var composerSendButton: XCUIElement { app.buttons["send-message-button"] }

    var deliveredReceipt: XCUIElement { app.staticTexts["Delivered"] }

    func messageBubble(_ text: String) -> XCUIElement { app.staticTexts[text] }

    // MARK: - Actions

    /// Opens the Send amount sheet on top of the conversation.
    func tapSendCash(from testCase: BaseUITestCase) {
        testCase.waitAndTap(sendCashButton)
    }

    /// Opens the composer, types `text`, and sends it.
    func sendMessage(_ text: String, from testCase: BaseUITestCase) {
        testCase.waitAndTap(sendMessageButton)
        testCase.waitUntilHittableAndTap(messageField)
        messageField.typeText(text)
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
