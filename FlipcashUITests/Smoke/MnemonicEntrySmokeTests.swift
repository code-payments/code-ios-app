//
//  MnemonicEntrySmokeTests.swift
//  FlipcashUITests
//

import XCTest

final class MnemonicEntrySmokeTests: BaseUITestCase {

    func testMnemonicEntry_showsWordCountAndEnablesLogin() {
        // IntroScreen — tap "Log In"
        waitAndTap(app.buttons["Log In"])

        // If saved accounts exist, tap through to manual entry
        let enterDifferentKey = app.buttons["Enter a Different Access Key"]
        if enterDifferentKey.waitForExistence(timeout: 5) {
            enterDifferentKey.tap()
        }

        // LoginScreen — "Enter Access Key Words"
        let title = app.staticTexts["Enter Access Key Words"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 30),
            "Expected to see the Enter Access Key Words screen"
        )

        // Type first few words to trigger autocomplete chips
        let textEditor = app.textViews.firstMatch
        XCTAssertTrue(
            textEditor.waitForExistence(timeout: 30),
            "Expected to find the mnemonic text input"
        )
        textEditor.tap()
        textEditor.typeText("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abou")

        // Verify autocomplete suggestions appear
        let aboutChip = app.buttons["about"]
        XCTAssertTrue(
            aboutChip.waitForExistence(timeout: 10),
            "Expected autocomplete suggestion 'about' to appear"
        )

        // Tap the autocomplete chip to complete the mnemonic
        aboutChip.tap()

        // Verify word count shows "12"
        let wordCount12 = app.staticTexts["12"]
        XCTAssertTrue(
            wordCount12.waitForExistence(timeout: 10),
            "Expected word count to show 12 after completing mnemonic"
        )

        // The "Log In" button should be enabled (valid 12-word mnemonic)
        let loginButton = app.buttons["Log In"]
        XCTAssertTrue(
            loginButton.isEnabled,
            "Expected the Log In button to be enabled with a valid 12-word mnemonic"
        )
    }
}
