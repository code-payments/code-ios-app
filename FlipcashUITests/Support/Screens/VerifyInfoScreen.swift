//
//  VerifyInfoScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the `VerifyInfoScreen` sheet — the phone + email
/// verification flow. There is no intro page: the sheet opens directly on
/// the first needed step (Enter Phone when the phone is unverified, Enter
/// Email otherwise).
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

    var emailStepTitle: XCUIElement {
        app.navigationBars["Verify Email"]
    }

    // MARK: - Assertions

    /// The unverified account must land directly on a verification step —
    /// no intro page. Which step depends on the account's phone state
    /// (server-side, not controlled by the test), so either root counts.
    func assertVerificationStepReached(timeout: TimeInterval = 10) {
        let either = NSPredicate(format: "identifier IN %@", ["Verify Phone Number", "Verify Email"])
        XCTAssertTrue(
            app.navigationBars.matching(either).firstMatch.waitForExistence(timeout: timeout),
            "Expected the verification sheet to open directly on Enter Phone or Enter Email"
        )
    }
}
