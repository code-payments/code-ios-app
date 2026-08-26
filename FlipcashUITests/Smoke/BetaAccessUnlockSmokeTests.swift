//
//  BetaAccessUnlockSmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// Smoke test for the version footer's beta-access easter egg and the one row
/// it reveals: You › My Account › Switch Accounts.
///
/// The unlock is the only way into the account switcher, and it is silent for
/// its first seven taps, so a regression in either half reads as "Switch
/// Accounts is gone". This drives both.
///
/// **State.** Beta access is stored in the keychain and outlives a launch;
/// `nukeForUITesting` does not clear it. The test locks it again at the end so
/// it leaves the simulator as it found it.
///
/// **Prerequisites:** the `FLIPCASH_UI_TEST_ACCESS_KEY` account only needs to be
/// loggable in.
@MainActor
final class BetaAccessUnlockSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testVersionFooter_tenTapsRevealSwitchAccounts() {
        let settings = SettingsUIScreen(app: app)

        assertMainScreenReached()
        settings.open(from: self)

        settings.tapVersionFooter(10, from: self)
        XCTAssertTrue(
            app.staticTexts["You are now a developer!"].waitForExistence(timeout: 5),
            "Expected the tenth tap to say beta access is unlocked"
        )

        settings.navigateToMyAccount(from: self)
        XCTAssertTrue(
            settings.switchAccountsRow.waitForExistence(timeout: 10),
            "Expected Switch Accounts on My Account once beta access is unlocked"
        )

        settings.leaveMyAccount(from: self)

        settings.tapVersionFooter(10, from: self)
        XCTAssertTrue(
            app.staticTexts["Beta features are hidden again"].waitForExistence(timeout: 5),
            "Expected ten more taps to lock beta access again"
        )

        settings.navigateToMyAccount(from: self)
        XCTAssertTrue(
            settings.blockedRow.waitForExistence(timeout: 10),
            "Expected My Account to be on screen"
        )
        XCTAssertFalse(
            settings.switchAccountsRow.exists,
            "Expected Switch Accounts to go away with beta access"
        )
    }
}
