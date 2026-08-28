//
//  BetaAccessUnlockSmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// Smoke test for the version footer's beta-access easter egg and the one row
/// it reveals: You › Advanced › Switch Accounts.
///
/// The unlock is the only way into the account switcher, and it is silent for
/// its first seven taps, so a regression in either half reads as "Switch
/// Accounts is gone". This drives both.
///
/// **State.** Beta access is stored in the keychain and outlives a launch;
/// `nukeForUITesting` does not clear it. The starting state is therefore
/// whatever the last run left behind — including a run that failed halfway
/// through the toggle — so the test locks it first and locks it again at the
/// end, and leaves the simulator as it found it.
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
        lockBetaAccessIfUnlocked(settings)

        settings.tapVersionFooter(10, from: self)
        XCTAssertTrue(
            settings.versionToast("You are now a developer!").waitForExistence(timeout: 5),
            "Expected the tenth tap to say beta access is unlocked"
        )

        settings.navigateToAdvancedFeatures(from: self)
        XCTAssertTrue(
            settings.switchAccountsRow.waitForExistence(timeout: 10),
            "Expected Switch Accounts on Advanced once beta access is unlocked"
        )

        settings.leaveAdvancedFeatures(from: self)

        settings.tapVersionFooter(10, from: self)
        XCTAssertTrue(
            settings.versionToast("Beta features are hidden again").waitForExistence(timeout: 5),
            "Expected ten more taps to lock beta access again"
        )

        settings.navigateToAdvancedFeatures(from: self)
        XCTAssertTrue(
            settings.accessKeyRow.waitForExistence(timeout: 10),
            "Expected Advanced to be on screen"
        )
        XCTAssertFalse(
            settings.switchAccountsRow.exists,
            "Expected Switch Accounts to go away with beta access"
        )
    }

    /// Locks beta access when a previous run left it unlocked, so the taps the
    /// test makes always start from the locked state and unlock.
    ///
    /// Switch Accounts is the readable signal for the stored flag: the footer
    /// itself says nothing until it is tapped, and a tap is the thing under
    /// test.
    private func lockBetaAccessIfUnlocked(_ settings: SettingsUIScreen) {
        settings.navigateToAdvancedFeatures(from: self)
        let isUnlocked = settings.switchAccountsRow.waitForExistence(timeout: 5)
        settings.leaveAdvancedFeatures(from: self)

        guard isUnlocked else { return }

        settings.tapVersionFooter(10, from: self)
        XCTAssertTrue(
            settings.versionToast("Beta features are hidden again").waitForExistence(timeout: 5),
            "Expected to lock the beta access a previous run left behind"
        )
    }
}
