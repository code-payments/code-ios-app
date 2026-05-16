//
//  VerifyInfoScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the `VerifyInfoScreen` sheet — the entry point of the
/// phone + email verification flow. Mounted by `BuyAmountScreen` /
/// `CurrencyCreationWizardScreen` when the user is unverified and taps
/// Apple Pay, and by `OnrampHostModifier` as a fallback when an email
/// verification deeplink arrives outside an active flow.
@MainActor
struct VerifyInfoUIScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    /// Heading text on the sheet's root. Unique enough to distinguish this
    /// screen from any other "Next"-button-bearing surface (the keypad's
    /// own Next button collides on label otherwise).
    var heading: XCUIElement {
        app.staticTexts["Verify Your Phone Number and Email to Continue"]
    }

    // MARK: - Assertions

    func assertReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            heading.waitForExistence(timeout: timeout),
            "Expected VerifyInfoScreen to appear"
        )
    }
}
