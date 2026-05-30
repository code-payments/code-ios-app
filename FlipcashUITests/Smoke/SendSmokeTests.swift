//
//  SendSmokeTests.swift
//  FlipcashUITests
//

import XCTest

final class SendSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }
    override var resetPermissions: [XCUIProtectedResource] { [.contacts] }

    func testSendFlow_picker_inviteFallback() {
        assertMainScreenReached()

        // Send is the 4th LargeButton on ScanBottomBar.
        waitAndTap(app.buttons["Send"])

        // Send gates phone entry behind a "Connect Your Phone Number" CTA;
        // onboarding drops you on the entry screen directly, so `allowPhone…`
        // alone can't reach the flow here. Tap through the CTA when the gate
        // is shown (skipped when the test account already has a verified phone).
        let connectPhone = app.buttons["Connect Your Phone Number"]
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

        waitAndTap(app.buttons["Invite"].firstMatch)

        // `MFMessageComposeViewController.canSendText()` returns `false`
        // on the simulator, so `RecipientPickerScreen.presentInvite(for:)`
        // takes the fallback path and calls `ShareSheet.present(url:)`.
        // `UIActivityViewController` hosts its actions as cells, not buttons,
        // since iOS 13.
        let copyCell = app.cells["Copy"]
        XCTAssertTrue(
            copyCell.waitForExistence(timeout: 10),
            "Expected the share-sheet fallback (UIActivityViewController) after tapping Invite"
        )

        // Dismiss the share sheet. Its close button's label ("Close") collides
        // with the Send screen's X behind it, so target it by identifier. Fall
        // back to "Cancel" (older iOS), then a downward swipe.
        let close  = app.buttons["header.closeButton"]
        let cancel = app.buttons["Cancel"]
        if close.exists {
            close.tap()
        } else if cancel.exists {
            cancel.tap()
        } else {
            app.swipeDown(velocity: .fast)
        }

        XCTAssertTrue(
            inviteHeader.waitForExistence(timeout: 10),
            "Expected `RecipientPickerScreen` to remain visible after dismissing the share sheet"
        )
    }
}
