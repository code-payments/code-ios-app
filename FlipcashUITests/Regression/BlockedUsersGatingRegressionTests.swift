//
//  BlockedUsersGatingRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Guards the beta gate on the Blocking feature: with `enableBlocking` off, the
/// "Blocked" row must not appear in Settings › My Account. Under `--ui-testing`
/// the app resets every beta flag from the launch argument, so an empty
/// `enabledBetaFlags` deterministically leaves blocking disabled regardless of
/// any prior run's on-disk flag cache.
///
/// **Prerequisites:** the `FLIPCASH_UI_TEST_ACCESS_KEY` account only needs to be
/// loggable in.
@MainActor
final class BlockedUsersGatingRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }
    // No enableBlocking — the launch-argument reset forces it off.

    /// My Account renders its always-present rows but omits the beta-gated
    /// Blocked row when Blocking is disabled.
    func testBlockedRow_hiddenWhenBlockingDisabled() {
        let settings = SettingsUIScreen(app: app)

        assertMainScreenReached()

        settings.open(from: self)
        settings.navigateToMyAccount(from: self)

        // Anchor on an always-present row so the absence check runs only once My
        // Account has actually rendered — otherwise a not-yet-loaded screen would
        // pass the negative assertion for the wrong reason.
        XCTAssertTrue(
            settings.accessKeyRow.waitForExistence(timeout: 30),
            "Expected My Account to render its always-present Access Key row"
        )
        XCTAssertFalse(
            settings.blockedRow.exists,
            "Expected the Blocked row to be hidden when the enableBlocking beta flag is off"
        )
    }
}
