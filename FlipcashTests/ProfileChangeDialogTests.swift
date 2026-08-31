//
//  ProfileChangeDialogTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("Profile change confirmation dialog")
struct ProfileChangeDialogTests {

    @Test("Names the field in the title and the confirming button", arguments: [
        (DialogItem.ProfileField.username, "Username"),
        (.displayName, "Display Name"),
        (.profilePicture, "Profile Picture"),
        (.minimumTip, "Minimum Tip"),
    ])
    func namesField(field: DialogItem.ProfileField, label: String) {
        let item = DialogItem.confirmProfileChange(field) {}

        #expect(item.title == "Change \(label)?")
        #expect(item.actions.first?.title == "Change \(label)")
    }

    @Test("States the change in the body", arguments: [
        (DialogItem.ProfileField.displayName, "This will change your display name"),
        (.profilePicture, "This will change your profile photo"),
        (.minimumTip, "This will change your minimum tip"),
    ])
    func statesTheChange(field: DialogItem.ProfileField, body: String) {
        let item = DialogItem.confirmProfileChange(field) {}

        #expect(item.subtitle == body)
    }

    @Test("Confirms over Cancel", arguments: [
        DialogItem.ProfileField.username,
        .displayName,
        .profilePicture,
        .minimumTip,
    ])
    func actions(field: DialogItem.ProfileField) {
        let item = DialogItem.confirmProfileChange(field) {}

        #expect(item.actions.count == 2)
        #expect(item.actions[1].title == "Cancel")
    }

    @Test("Runs the caller's work only once the change is confirmed")
    func confirmAction_runsHandler() {
        var confirmed = false
        let item = DialogItem.confirmProfileChange(.username) { confirmed = true }

        #expect(confirmed == false)
        item.actions[0].action()
        #expect(confirmed == true)
    }

    @Test("Cancel leaves the caller's work unrun")
    func cancelAction_doesNotRunHandler() {
        var confirmed = false
        let item = DialogItem.confirmProfileChange(.username) { confirmed = true }

        item.actions[1].action()
        #expect(confirmed == false)
    }

    /// The only one of the four that can cost the user something they can't
    /// take back, so it is the only one that says so.
    @Test("Only the username warns that the old value may be gone for good")
    func usernameWarnsAboutLosingTheHandle() {
        let username = DialogItem.confirmProfileChange(.username) {}
        #expect(username.subtitle?.contains("You might not be able to get your old username back") == true)

        for field in [DialogItem.ProfileField.displayName, .profilePicture, .minimumTip] {
            let item = DialogItem.confirmProfileChange(field) {}
            #expect(item.subtitle?.contains("get your old") == false)
        }
    }

    /// The banner carries the warning, so only the irreversible change is red.
    @Test("Red banner for the username, grey for the reversible three")
    func usernameAloneIsDestructive() {
        let username = DialogItem.confirmProfileChange(.username) {}
        #expect(username.style == .destructive)
        #expect(username.actions[0].kind == .destructive)

        for field in [DialogItem.ProfileField.displayName, .profilePicture, .minimumTip] {
            let item = DialogItem.confirmProfileChange(field) {}
            #expect(item.style == .standard)
            #expect(item.actions[0].kind == .standard)
        }
    }

    @Test("Not an error worth reporting", arguments: [
        DialogItem.ProfileField.username,
        .displayName,
        .profilePicture,
        .minimumTip,
    ])
    func untracked(field: DialogItem.ProfileField) {
        #expect(DialogItem.confirmProfileChange(field) {}.tracked == false)
    }
}
