//
//  SettingsScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the settings list and its sub-screens.
///
/// The tab-bar UI has no Settings sheet: `YouScreen` renders the list inline
/// under the tip card, so "open settings" is the You tab plus a scroll. Only
/// **My Account** and **Advanced** live here now — Add Money and Withdraw Money
/// moved to the Wallet tab's tiles, on `WalletScreen`.
@MainActor
struct SettingsUIScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    /// The You tab's scrolling content, the container the rows are scrolled in.
    var scrollView: XCUIElement { app.scrollViews.firstMatch }

    var myAccountRow: XCUIElement { app.buttons["My Account"] }
    var advancedFeaturesRow: XCUIElement { app.buttons["Advanced"] }
    var accessKeyRow: XCUIElement { app.buttons["Access Key"] }
    var applicationLogsRow: XCUIElement { app.buttons["Application Logs"] }

    /// The My Account row that opens the Blocked list.
    var blockedRow: XCUIElement { app.buttons["Blocked"] }

    // MARK: - Actions

    /// Opens the You tab, which hosts the settings list.
    func open(from testCase: BaseUITestCase) {
        testCase.waitAndTap(app.buttons["You"])
    }

    /// Navigates to My Account sub-screen. The rows render below the tip card,
    /// so they start off-screen and have to be scrolled to rather than tapped
    /// blind.
    func navigateToMyAccount(from testCase: BaseUITestCase) {
        testCase.scrollUpToAndTap(myAccountRow, in: scrollView)
    }

    /// Navigates to Advanced Features sub-screen.
    func navigateToAdvancedFeatures(from testCase: BaseUITestCase) {
        testCase.scrollUpToAndTap(advancedFeaturesRow, in: scrollView)
    }
}
