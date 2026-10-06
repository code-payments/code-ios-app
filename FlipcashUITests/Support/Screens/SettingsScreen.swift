//
//  SettingsScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the settings list and its sub-screens.
///
/// Settings is pushed from the gear on the You tab, so "open settings" is the
/// You tab plus the gear. Add Money and Withdraw Money live on the Wallet tab's
/// tiles, on `WalletScreen`.
@MainActor
struct SettingsUIScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    /// The Settings list's scrolling content, the container the rows are scrolled in.
    var scrollView: XCUIElement { app.scrollViews.firstMatch }

    /// The gear on the You tab that pushes Settings.
    var gear: XCUIElement { app.buttons["you-settings"] }

    var accessKeyRow: XCUIElement { app.buttons["Access Key"] }
    var applicationLogsRow: XCUIElement { app.buttons["Application Logs"] }

    /// The Profile row that opens Edit Profile.
    var editProfileRow: XCUIElement { app.buttons["settings-edit-profile"] }

    /// Edit Profile's row that opens the display-name editor.
    var displayNameRow: XCUIElement { app.buttons["edit-profile-name"] }

    /// The Privacy row that opens the Blocked list.
    var blockedRow: XCUIElement { app.buttons["Blocked"] }

    /// The Advanced-section row that opens the account switcher — drawn only once the
    /// version footer has unlocked beta access.
    var switchAccountsRow: XCUIElement { app.buttons["account-switch-accounts-row"] }

    /// The version string at the foot of Settings, which doubles as the
    /// beta-access easter egg.
    var versionFooter: XCUIElement { app.buttons["you-version-footer"] }

    /// The toast the version footer raises, matched on the message it carries.
    ///
    /// Identifier and label are matched in one predicate because the toast
    /// clears itself two seconds after it appears: finding the element first
    /// and reading its label second races that timer.
    func versionToast(_ message: String) -> XCUIElement {
        app.staticTexts
            .matching(
                NSPredicate(
                    format: "identifier == %@ AND label == %@",
                    "you-version-toast",
                    message
                )
            )
            .firstMatch
    }

    // MARK: - Actions

    /// Opens the You tab.
    func openYouTab(from testCase: BaseUITestCase) {
        testCase.waitAndTap(app.tabBars.buttons["You"].firstMatch)
    }

    /// Opens Settings: the You tab, then the gear.
    func open(from testCase: BaseUITestCase) {
        openYouTab(from: testCase)
        testCase.waitAndTap(gear)
    }

    /// Taps the version footer `times` times, scrolling it into view first.
    /// Ten taps toggle beta access.
    func tapVersionFooter(_ times: Int, from testCase: BaseUITestCase) {
        testCase.scrollUpToAndTap(versionFooter, in: scrollView)
        for _ in 1..<times {
            versionFooter.tap()
        }
    }
}
