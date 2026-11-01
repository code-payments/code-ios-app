//
//  PinnedListSmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// Drives the pinned messages sheet's hit targets: in a row, only the bubble (jump) and Unpin
/// respond. The avatar, the name, the "Pinned by" line and the row's empty width must do nothing.
///
/// **Prerequisites:** the `FLIPCASH_UI_TEST_ACCESS_KEY` account (XCTests) has a tip DM with Brandon
/// McAnsh, where either member may pin. The test pins one message it sends and unpins it again;
/// without the DM it skips rather than fails.
@MainActor
final class PinnedListSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    private var conversation: ConversationUIScreen { ConversationUIScreen(app: app) }
    private var sheetTitle: XCUIElement { app.staticTexts["Pinned Messages"] }

    override func setUp() async throws {
        try await super.setUp()
        executionTimeAllowance = 600
    }

    /// Taps around a pinned row's bubble leave the sheet open; a tap on the bubble's edge closes it.
    func testPinnedRow_onlyTheBubbleAndUnpinRespond() throws {
        try openConversation()

        let text = Self.uniqueText("pinned")
        conversation.sendMessage(text, from: self)
        conversation.assertMessageDelivered(text)
        conversation.openMenu(on: text, from: self)
        waitAndTap(app.buttons["Pin"].firstMatch, timeout: 15, "Expected Pin in the message menu")
        defer { unpin(text) }

        openList()
        let bubble = pinnedBubble(text)
        XCTAssertTrue(bubble.waitForExistence(timeout: 15), "Expected the pinned row's bubble. On screen: [\(visibleText())]")
        waitForStableFrame(bubble)
        XCTAssertTrue(bubble.label.hasPrefix("Jump to message"), "Expected the bubble to read as a jump, got '\(bubble.label)'")

        let pinnedLine = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Pinned by'")).firstMatch
        XCTAssertTrue(pinnedLine.exists, "Expected the 'Pinned by' line as plain text")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Pinned by'")).firstMatch.exists)

        let frame = bubble.frame
        let origin = bubble.coordinate(withNormalizedOffset: .zero)
        let inert: [(String, CGVector)] = [
            ("avatar", CGVector(dx: -24, dy: frame.height - 12)),
            ("name", CGVector(dx: 8, dy: -8)),
            ("pinned line", CGVector(dx: 8, dy: frame.height + 10)),
            // The pinned message is our own, so the row's empty width is left of the bubble; right
            // of it there is only the 12pt row inset, and 24pt past the edge lands off the sheet.
            ("empty row space", CGVector(dx: -frame.minX / 2, dy: frame.height / 2)),
        ]
        for (name, offset) in inert {
            origin.withOffset(offset).tap()
            XCTAssertTrue(
                sheetTitle.waitForExistence(timeout: 2) && bubble.exists,
                "Tapping the \(name) closed the sheet; only the bubble and Unpin may respond"
            )
        }

        origin.withOffset(CGVector(dx: frame.width - 6, dy: frame.height / 2)).tap()
        XCTAssertTrue(
            sheetTitle.waitForNonExistence(timeout: 5),
            "Expected a tap on the bubble's edge to close the sheet and jump"
        )
    }

    // MARK: - Helpers

    private func openList() {
        let barButton = app.buttons["pin-bar-list"]
        let toolbarButton = app.buttons["pin-toolbar-button"]
        if barButton.waitForExistence(timeout: 15) {
            barButton.tap()
        } else {
            waitAndTap(toolbarButton, timeout: 15, "Expected a way to open the pinned list")
        }
        XCTAssertTrue(sheetTitle.waitForExistence(timeout: 10), "Expected the pinned list. On screen: [\(visibleText())]")
    }

    /// Unpins `text` from the sheet so the DM keeps its pin slots free for the next run. The sheet,
    /// not the message menu: after the jump the transcript can hold the text twice.
    private func unpin(_ text: String) {
        if !sheetTitle.exists { openList() }
        let bubble = pinnedBubble(text)
        guard bubble.waitForExistence(timeout: 10) else { return }
        let bubbleBottom = bubble.frame.maxY
        let unpin = app.buttons.matching(NSPredicate(format: "label == 'Unpin'")).allElementsBoundByIndex
            .filter { $0.frame.minY >= bubbleBottom - 1 }
            .min { $0.frame.minY < $1.frame.minY }
        guard let unpin else { return XCTFail("Expected an Unpin under '\(text)'") }
        unpin.tap()
        XCTAssertTrue(bubble.waitForNonExistence(timeout: 15), "Expected '\(text)' to leave the pinned list")
    }

    private func pinnedBubble(_ text: String) -> XCUIElement {
        app.buttons.matching(identifier: "chat-message-cell-bubble")
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func openConversation() throws {
        assertMainScreenReached()

        let chats = TipsUIScreen(app: app)
        chats.open(from: self)

        guard let row = chats.sendTargetDMRow(timeout: 30) else {
            throw XCTSkip("No DM with \(TipsUIScreen.sendTargetName) — skipping the pinned list suite. On screen: [\(visibleText())]")
        }
        row.tap()

        XCTAssertTrue(
            conversation.messageField.waitForExistence(timeout: 30),
            "Expected the conversation's composer. On screen: [\(visibleText())]"
        )
        conversation.clearDraft()
    }

    /// A per-run body, so a bubble query can never match a message left behind by an earlier run.
    private static func uniqueText(_ prefix: String) -> String {
        "\(prefix) \(Int(Date().timeIntervalSince1970 * 1000) % 1_000_000)"
    }
}
