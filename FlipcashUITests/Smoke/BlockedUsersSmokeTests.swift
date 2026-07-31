//
//  BlockedUsersSmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// Smoke tests for the Blocked users list reached from Settings › My Account ›
/// Blocked, with the `enableBlocking` beta flag on.
///
/// **Scope.** These cover the navigation into the list and that the screen loads
/// — the parts most likely to regress from a routing or beta-gate change. The
/// block/unblock *action* itself is intentionally not driven here: it requires a
/// live tip-DM conversation fixture (the Block affordance only appears on a tip
/// DM's profile) and committing it would mutate the standing account's server
/// blocklist, which the tip smoke tests deliberately never do. That logic is
/// covered by the unit `BlocklistControllerTests` against a fake backend.
///
/// **Prerequisites:** the `FLIPCASH_UI_TEST_ACCESS_KEY` account only needs to be
/// loggable in; the test does not depend on its blocklist contents.
@MainActor
final class BlockedUsersSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }
    override var enabledBetaFlags: [String] { ["enableBlocking"] }

    /// Main → Settings → My Account → Blocked lands on the Blocked list and it
    /// loads its state (empty or populated) without hanging.
    func testBlockedUsers_reachableFromMyAccount() {
        let settings = SettingsUIScreen(app: app)
        let blocked = BlockedUsersUIScreen(app: app)

        assertMainScreenReached()

        settings.open(from: self)
        settings.navigateToMyAccount(from: self)

        // The Blocked row is gated on `enableBlocking`, which this test enables.
        waitAndTap(settings.blockedRow)

        blocked.assertLoaded(from: self)
    }
}
