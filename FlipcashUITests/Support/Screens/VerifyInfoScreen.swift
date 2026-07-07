//
//  VerifyInfoScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the `VerifyInfoScreen` sheet — the phone + email
/// verification flow. There is no intro page: the sheet opens directly on
/// the first needed step (Enter Phone when the phone is unverified, Enter
/// Email otherwise). Mounted by the Add Money amount screen when the user
/// is unverified and taps Apple Pay, and by `OnrampHostModifier` as a
/// fallback when an email verification deeplink arrives outside an active
/// flow.
@MainActor
struct VerifyInfoUIScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    var phoneStepTitle: XCUIElement {
        app.navigationBars["Verify Phone Number"]
    }

    var phoneField: XCUIElement {
        app.textFields["Phone Number"]
    }

    // MARK: - Assertions

    /// The fully-unverified account (no phone, no email) must land directly
    /// on the phone step — no intro page in between.
    func assertPhoneStepReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            phoneStepTitle.waitForExistence(timeout: timeout),
            "Expected the verification sheet to open directly on Enter Phone"
        )
        XCTAssertTrue(
            phoneField.exists,
            "Expected the phone number field on the verification root"
        )
    }
}
