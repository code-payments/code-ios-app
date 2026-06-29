//
//  RecipientPickerUIScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the Send flow's recipient picker. Opens Send, clears the
/// entry gates, and selects an on-Flipcash recipient.
@MainActor
struct RecipientPickerUIScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    /// The Send button on the ScanBottomBar (gated by the `enableSend` flag).
    var sendButton: XCUIElement { app.buttons["scan-send-button"] }

    /// A recipient row whose accessibility label starts with `name`.
    func recipientRow(named name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    // MARK: - Actions

    /// Opens the Send sheet from the main screen.
    func open(from testCase: BaseUITestCase) {
        testCase.waitAndTap(sendButton)
    }

    /// Clears the connect-phone CTA, the phone + contacts gates, and the
    /// on-Flipcash nudge. Each step no-ops when already satisfied.
    func passEntryGates(from testCase: BaseUITestCase) {
        let connectPhone = app.buttons["Next"]
        if connectPhone.waitForExistence(timeout: 5) {
            connectPhone.tap()
        }
        testCase.allowPhoneVerificationIfNeeded()
        testCase.allowContactsIfNeeded()

        // The nudge sits in its own window over the picker, so dismiss it first.
        let nudge = app.buttons["OK"]
        if nudge.waitForExistence(timeout: 5) {
            nudge.tap()
        }
    }

    /// Selects the recipient row for `name`, opening their conversation. Scrolls
    /// as insurance when it isn't already near the top of the feed.
    func selectRecipient(named name: String) {
        let row = recipientRow(named: name)
        if !row.waitForExistence(timeout: 20) {
            for _ in 0..<6 where !row.exists {
                app.swipeUp()
            }
        }
        XCTAssertTrue(
            row.exists,
            "Expected '\(name)' in the Send recipient picker — the test account must reach them as an on-Flipcash contact or chat"
        )
        row.tap()
    }
}
