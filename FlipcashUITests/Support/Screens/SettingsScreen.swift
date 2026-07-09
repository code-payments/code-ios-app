//
//  SettingsScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the SettingsScreen.
/// Provides access to settings menu items and sub-screens.
@MainActor
struct SettingsUIScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    var myAccountRow: XCUIElement { app.buttons["My Account"] }
    var withdrawMoneyButton: XCUIElement { app.buttons["Withdraw Money"] }
    var advancedFeaturesRow: XCUIElement { app.buttons["Advanced"] }
    var accessKeyRow: XCUIElement { app.buttons["Access Key"] }
    var addMoneyButton: XCUIElement { app.buttons["Add Money"] }
    var applicationLogsRow: XCUIElement { app.buttons["Application Logs"] }

    // MARK: - Actions

    /// Opens Settings from the main screen.
    func open(from testCase: BaseUITestCase) {
        testCase.waitAndTap(app.buttons["Settings"])
    }

    /// Navigates to My Account sub-screen.
    func navigateToMyAccount(from testCase: BaseUITestCase) {
        testCase.waitAndTap(myAccountRow)
    }

    /// Navigates to Advanced Features sub-screen.
    func navigateToAdvancedFeatures(from testCase: BaseUITestCase) {
        testCase.waitAndTap(advancedFeaturesRow)
    }
}
