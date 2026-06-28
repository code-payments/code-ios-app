//
//  SendSmokeTests.swift
//  FlipcashUITests
//

import XCTest

final class SendSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }
    override var resetPermissions: [XCUIProtectedResource] { [.contacts] }
    override var enabledBetaFlags: [String] { ["enableSend"] }

    func testSendFlow_picker_inviteFallback() {
        assertMainScreenReached()

        // Send is the 4th LargeButton on ScanBottomBar.
        waitAndTap(app.buttons["Send"])

        // Send gates phone entry behind a "Next" CTA on the connect-phone
        // pitch; onboarding drops you on the entry screen directly, so
        // `allowPhone…` alone can't reach the flow here. Tap through the CTA
        // when the gate is shown (skipped when the test account already has a
        // verified phone).
        let connectPhone = app.buttons["Next"]
        if connectPhone.waitForExistence(timeout: 5) {
            connectPhone.tap()
        }

        // The helpers are idempotent — they no-op when the gate is already
        // satisfied for the test account.
        allowPhoneVerificationIfNeeded()
        allowContactsIfNeeded()

        // RecipientPickerScreen renders one of three states. Wait for any of
        // them so the test is resilient to whether the test account has any
        // matched/invitable contacts at run time.
        let onFlipcashHeader = app.staticTexts["On Flipcash"]
        let inviteHeader     = app.staticTexts["Not on Flipcash Yet"]
        let emptyState       = app.staticTexts["No Contacts Found"]
        // Limited access (iOS 18+) with nothing shared renders its own state.
        let limitedEmptyState = app.staticTexts["No Contacts Shared"]

        func pickerRendered() -> Bool {
            onFlipcashHeader.exists || inviteHeader.exists
                || emptyState.exists || limitedEmptyState.exists
        }

        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if pickerRendered() { break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertTrue(
            pickerRendered(),
            "Expected `RecipientPickerScreen` to render an On-Flipcash header, an Invite header, or an empty state"
        )

        // The invite-fallback path requires at least one row in the Invite
        // section. If the picker is empty (simulator without contacts), the
        // header assertions above stand on their own — skip the rest.
        guard inviteHeader.exists else { return }

        waitAndTap(app.buttons["Anna Haro, (555) 522-8243"].firstMatch)

        // `MFMessageComposeViewController.canSendText()` returns `false` on the
        // simulator, so the invite row is a `ShareLink` that presents the system
        // share sheet. `UIActivityViewController` hosts its actions as cells, not
        // buttons, since iOS 13.
        let copyCell = app.cells["Copy"]
        XCTAssertTrue(
            copyCell.waitForExistence(timeout: 20),
            "Expected the share-sheet fallback (UIActivityViewController) after tapping Invite"
        )

        // Tap "Copy" to complete the share and dismiss the sheet (mirrors
        // CashLinkRegressionTests). A completed action is a deterministic
        // dismiss that returns to the picker — unlike a swipe or tapping a
        // close button whose label collides with the Send screen's X.
        copyCell.tap()

        XCTAssertTrue(
            inviteHeader.waitForExistence(timeout: 15),
            "Expected `RecipientPickerScreen` to remain visible after dismissing the share sheet"
        )
    }
}
