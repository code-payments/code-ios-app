//
//  BlockUnblockSmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// End-to-end round-trip for the Blocking feature: block a user from their tip
/// DM, confirm the conversation disappears from the Tips list, then unblock them
/// from Settings and confirm the block is cleared.
///
/// **Fixture (non-mutating by design).** The Block affordance only exists on a
/// tip-DM conversation, so the test drives whatever tip DM the standing
/// `FLIPCASH_UI_TEST_ACCESS_KEY` account already has — it never sends a tip and
/// captures the counterpart's name dynamically. With no tip DM in the feed the
/// test skips rather than fabricating one. The block/unblock round-trip restores
/// the account's blocklist to its starting state; `tearDown` re-runs the unblock
/// best-effort if an assertion fails after the block lands, so a failed run never
/// leaves the shared account with a user blocked.
///
/// **Prerequisites:** the standing account needs a tip profile and at least one
/// tip DM in its Tips list.
@MainActor
final class BlockUnblockSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }
    // The Block affordance needs `enableBlocking`; Tips is always on now.
    override var enabledBetaFlags: [String] { ["enableBlocking"] }

    /// The counterpart blocked during the test, cleared once unblocked. Non-nil
    /// in `tearDown` means the round-trip failed after the block — clean it up.
    private var blockedName: String?

    override func setUp() async throws {
        try await super.setUp()
        // The full round-trip crosses several screens and two sheets.
        executionTimeAllowance = 600
    }

    /// Blocks the first tip-DM counterpart, asserts their chat leaves the Tips
    /// list, then unblocks them from Settings and asserts the block is gone.
    func testBlock_hidesTipConversation_thenUnblockRestores() throws {
        let tips = TipsUIScreen(app: app)
        let settings = SettingsUIScreen(app: app)
        let blocked = BlockedUsersUIScreen(app: app)

        assertMainScreenReached()

        // MARK: Reach a tip DM (skip when the account has none).
        tips.open(from: self)
        guard let row = tips.firstConversationRow() else {
            throw XCTSkip("No tip DM in the standing account's Tips list — skipping the block/unblock round-trip")
        }
        // The row label is the counterpart's display name, plus an ", unread
        // messages" suffix when unread. Strip it to the bare name, which the
        // conversation title, the block dialog, and the blocked-list row share.
        let name = row.label.replacingOccurrences(of: ", unread messages", with: "")
        XCTAssertFalse(name.isEmpty, "Expected the tip conversation row to carry the counterpart's name")
        row.tap()

        // MARK: Open the counterpart's profile from the conversation.
        // The tip DM shows Send Cash — wait for it so the transcript has loaded
        // before reaching for the title.
        XCTAssertTrue(
            app.buttons["send-cash-button"].waitForExistence(timeout: 30),
            "Expected the tip DM conversation to open with Send Cash"
        )
        // The nav-title item is a button (label = the name) only when blocking is
        // enabled and the tip counterpart resolves — both hold here.
        let titleButton = app.buttons[name].firstMatch
        XCTAssertTrue(
            titleButton.waitForExistence(timeout: 15),
            "Expected the conversation title to be a tappable profile button for '\(name)'"
        )
        titleButton.tap()

        // MARK: Block from the profile screen.
        waitAndTap(app.buttons["Block"], timeout: 30, "Expected the Block row on the profile screen")
        let blockDialog = app.otherElements
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "Block "))
            .firstMatch
        XCTAssertTrue(blockDialog.waitForExistence(timeout: 10), "Expected the block confirmation dialog")
        blockDialog.buttons["Block"].tap()
        blockedName = name

        // MARK: The chat leaves the Tips list.
        // Block returns to the Tips root; the reconcile hides the conversation,
        // and there is no empty-state label, so assert the row's absence.
        let hiddenRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(
            hiddenRow.waitForNonExistence(timeout: 20),
            "Expected '\(name)' tip conversation to disappear from the Tips list after blocking"
        )

        // MARK: Unblock from Settings › My Account › Blocked.
        tips.close(from: self)
        settings.open(from: self)
        settings.navigateToMyAccount(from: self)
        waitAndTap(settings.blockedRow)
        blocked.assertLoaded(from: self)

        let blockedRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(
            blockedRow.waitForExistence(timeout: 20),
            "Expected '\(name)' to appear in the Blocked list"
        )
        blockedRow.tap()

        let unblockDialog = app.otherElements
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "Unblock "))
            .firstMatch
        XCTAssertTrue(unblockDialog.waitForExistence(timeout: 10), "Expected the unblock confirmation dialog")
        unblockDialog.buttons["Unblock"].tap()

        // MARK: The block is cleared.
        XCTAssertTrue(
            blockedRow.waitForNonExistence(timeout: 20),
            "Expected '\(name)' to leave the Blocked list after unblocking"
        )
        blockedName = nil
    }

    override func tearDown() async throws {
        // A block that landed but wasn't undone (an assertion failed mid-flow)
        // would leave the shared account dirty. Relaunch clean and remove it
        // best-effort; never assert, so teardown can't mask the real failure.
        if let name = blockedName {
            blockedName = nil
            app.launch()
            try? loginTestAccount()
            bestEffortUnblock(named: name)
        }
        try await super.tearDown()
    }

    /// Navigates Settings › My Account › Blocked and unblocks `name` if present,
    /// tolerating every step so a failed test's teardown stays quiet.
    private func bestEffortUnblock(named name: String) {
        let settings = SettingsUIScreen(app: app)
        guard app.buttons["Settings"].waitForExistence(timeout: 30) else { return }
        app.buttons["Settings"].tap()
        guard settings.myAccountRow.waitForExistence(timeout: 10) else { return }
        settings.myAccountRow.tap()
        guard settings.blockedRow.waitForExistence(timeout: 10) else { return }
        settings.blockedRow.tap()

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        guard row.waitForExistence(timeout: 15) else { return }
        row.tap()
        let dialog = app.otherElements
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "Unblock "))
            .firstMatch
        guard dialog.waitForExistence(timeout: 10) else { return }
        dialog.buttons["Unblock"].tap()
    }
}
