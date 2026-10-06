//
//  TipsSmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// Rides a tipcard link from the link to the profile it opens, without committing
/// a transfer. The tipcard deeplink stands in for scanning, which a simulator
/// camera can't do.
///
/// **Prerequisites:** the `FLIPCASH_UI_TEST_ACCESS_KEY` account needs a tip
/// profile, and the standing recipient below must keep its tip profile.
@MainActor
final class TipsSmokeTests: BaseUITestCase {

    /// The standing tip recipient's user id — a public identifier, the tip
    /// counterpart of "Raul Riera" in the send tests. From that account's
    /// tipcard link.
    private static let recipientID = "db4c2358-e706-484c-85df-3c90407096ea"

    override var requiresAuthentication: Bool { true }

    override func setUp() async throws {
        try await super.setUp()
        // The deeplink retries call `app.open`, which relaunches the app if
        // it isn't foremost — and a relaunch replays the stored launch
        // arguments, whose `--ui-testing` nuke would log the account out
        // mid-test. Clear them so any relaunch resumes the session (the beta
        // flag survives via its on-disk cache).
        app.launchArguments = []
        // The full flow runs past XCTest's 2-minute default.
        executionTimeAllowance = 600
    }

    /// A tipcard link shows the recipient's card and then opens their
    /// profile, whose pinned button starts or opens the chat. The profile
    /// proves the landing; no transfer is made.
    func testTipDeeplink_opensTheProfile() throws {
        assertMainScreenReached()

        app.open(URL(string: "flipcash://tip/\(Self.recipientID)")!)

        let pinnedAction = app.buttons["profile-pinned-action"]
        XCTAssertTrue(
            pinnedAction.waitForExistence(timeout: 180),
            "The recipient's profile never appeared. On screen: [\(visibleText())]"
        )
    }
}
