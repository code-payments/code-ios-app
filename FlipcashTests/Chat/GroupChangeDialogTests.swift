//
//  GroupChangeDialogTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("Group change confirmation dialog")
struct GroupChangeDialogTests {

    @Test("Names the field in the title and the confirming button", arguments: [
        (DialogItem.GroupField.name, "Group Name"),
        (.picture, "Group Picture"),
    ])
    func namesField(field: DialogItem.GroupField, label: String) {
        let item = DialogItem.confirmGroupChange(field) {}

        #expect(item.title == "Change \(label)?")
        #expect(item.actions.first?.title == "Change \(label)")
    }

    /// The rows say "Name" and "Picture"; the dialog says whose. Covering the screen that gave
    /// those labels their context is what makes the longer form necessary.
    @Test("Says the group's, not the user's own", arguments: [
        DialogItem.GroupField.name,
        .picture,
    ])
    func qualifiesTheFieldAsTheGroups(field: DialogItem.GroupField) {
        let item = DialogItem.confirmGroupChange(field) {}

        #expect(item.title?.contains("Group") == true)
        #expect(item.subtitle?.contains("your") == false)
    }

    @Test("States the change in the body", arguments: [
        (DialogItem.GroupField.name, "This will change the group name for everyone in it"),
        (.picture, "This will change the group picture for everyone in it"),
    ])
    func statesTheChange(field: DialogItem.GroupField, body: String) {
        let item = DialogItem.confirmGroupChange(field) {}

        #expect(item.subtitle == body)
    }

    @Test("Confirms over Cancel", arguments: [
        DialogItem.GroupField.name,
        .picture,
    ])
    func actions(field: DialogItem.GroupField) {
        let item = DialogItem.confirmGroupChange(field) {}

        #expect(item.actions.count == 2)
        #expect(item.actions[1].title == "Cancel")
    }

    @Test("Runs the caller's work only once the change is confirmed", arguments: [
        DialogItem.GroupField.name,
        .picture,
    ])
    func confirmAction_runsHandler(field: DialogItem.GroupField) {
        var confirmed = false
        let item = DialogItem.confirmGroupChange(field) { confirmed = true }

        #expect(confirmed == false)
        item.actions[0].action()
        #expect(confirmed == true)
    }

    @Test("Cancel leaves the caller's work unrun", arguments: [
        DialogItem.GroupField.name,
        .picture,
    ])
    func cancelAction_doesNotRunHandler(field: DialogItem.GroupField) {
        var confirmed = false
        let item = DialogItem.confirmGroupChange(field) { confirmed = true }

        item.actions[1].action()
        #expect(confirmed == false)
    }

    /// Both edits land on everyone in the group at once, so both carry the alert's weight rather
    /// than the grey banner the reversible profile fields use.
    @Test("Red banner for both", arguments: [
        DialogItem.GroupField.name,
        .picture,
    ])
    func bothAreDestructive(field: DialogItem.GroupField) {
        let item = DialogItem.confirmGroupChange(field) {}

        #expect(item.style == .destructive)
        #expect(item.actions[0].kind == .destructive)
    }

    @Test("Not an error worth reporting", arguments: [
        DialogItem.GroupField.name,
        .picture,
    ])
    func untracked(field: DialogItem.GroupField) {
        #expect(DialogItem.confirmGroupChange(field) {}.tracked == false)
    }
}
