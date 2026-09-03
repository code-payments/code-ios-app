//
//  DisplayNameSmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// Covers the display name and the tip card it earns: a freshly registered
/// account lands on the You tab with a card it can share, and the name behind
/// that card can be changed from My Account.
///
/// This replaces the old profile-creation walkthrough (Tips intro → name →
/// photo → tipcard), which has no subject left. The name step is mandatory
/// during onboarding now, so no account ever reaches the app without one — the
/// You tab's "Start Receiving Tips" prompt and the Chats tab's intro are both
/// unreachable — and the photo step has no caller: `ProfileNameScreen` goes
/// straight from the name to the card because the card omits the photo.
///
/// It registers a new account rather than using the standing one: the card's
/// first appearance is only observable on an account that has just been made,
/// and renaming a shared account would leave it renamed.
@MainActor
final class DisplayNameSmokeTests: BaseUITestCase {

    override func setUp() async throws {
        try await super.setUp()
        // Registration plus a second `SetDisplayName` round-trip runs past
        // XCTest's 2-minute default, which kills the test before any assertion
        // can report.
        executionTimeAllowance = 300
    }

    func testDisplayName_yieldsTipCard_andCanBeChanged() throws {
        let settings = SettingsUIScreen(app: app)

        // Onboarding's mandatory name step sets the display name, so the account
        // arrives already tippable.
        createFreshAccount()

        // MARK: The card is there, with its actions.
        settings.open(from: self)
        XCTAssertTrue(
            app.buttons["you-share-button"].waitForExistence(timeout: 30),
            "Expected the tip card's Share action on a named account. On screen: [\(visibleText())]"
        )
        XCTAssertTrue(
            app.buttons["you-download-button"].exists,
            "Expected the tip card's Download action alongside Share"
        )
        XCTAssertTrue(
            app.buttons["you-fullscreen-button"].exists,
            "Expected the card itself, not the name-less setup prompt"
        )

        // MARK: Change the name from My Account.
        settings.navigateToMyAccount(from: self)
        waitAndTap(settings.displayNameRow)

        let save = app.buttons["profile-name-next-button"]
        XCTAssertTrue(save.waitForExistence(timeout: 30), "Expected the name editor")

        // The editor is seeded with the name already on the profile, and Save
        // takes an actual change — so it starts disabled on the seeded name.
        let field = app.textFields["Your Name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Expected the name field")
        XCTAssertFalse(save.isEnabled, "Save must start disabled on the name already on the profile")

        field.tap()
        let seeded = (field.value as? String) ?? ""
        XCTAssertFalse(seeded.isEmpty, "Expected the editor to be seeded with the current name")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: seeded.count))
        XCTAssertFalse(save.isEnabled, "Save must stay disabled while the name is empty")

        field.typeText("Renamed \(Int.random(in: 1_000...9_999))")
        XCTAssertTrue(save.isEnabled, "Save must enable once the name is valid and changed")
        save.tap()

        // Replacing a name that is already set is confirmed first; only the
        // first name set during onboarding saves straight through. The editor
        // stays up behind the dialog until it is answered.
        let confirmDialog = app.otherElements["Change Display Name?"]
        XCTAssertTrue(
            confirmDialog.waitForExistence(timeout: 30),
            "Expected the rename confirmation dialog. On screen: [\(visibleText())]"
        )
        waitUntilHittableAndTap(
            confirmDialog.buttons["Change Display Name"],
            "Expected the dialog's Change Display Name action to be tappable"
        )

        // `ProfileNameScreen(completion: .back)` pops itself only once
        // `SetDisplayName` returns, so landing back on My Account is proof the
        // new name was accepted and moderated — a rejection keeps the editor up
        // behind a dialog. It pops just the one screen, so this is My Account
        // rather than the You tab root.
        XCTAssertTrue(
            settings.displayNameRow.waitForExistence(timeout: 60),
            "Expected the name editor to pop back to My Account once the name saved. On screen: [\(visibleText())]"
        )

        // MARK: The card survives the rename.
        // Unwind the last screen by hand: the tab bar stays hidden while the
        // You tab has a stack, so there is no You button to tap back to.
        waitAndTap(app.navigationBars.buttons.firstMatch)
        assertMainScreenReached(timeout: 30, "Expected the You tab root after backing out of My Account")
        XCTAssertTrue(
            app.buttons["you-share-button"].waitForExistence(timeout: 30),
            "Expected the tip card still on the You tab after renaming"
        )
    }
}
