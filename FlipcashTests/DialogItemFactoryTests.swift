//
//  DialogItemFactoryTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("DialogItem factory semantics")
struct DialogItemFactoryTests {

    @Test(".error produces a tracked destructive item with a default destructive OK action")
    func error_singleArg_destructiveStyleTrackedDefaultDestructiveOK() {
        let item = DialogItem.error(title: "x", subtitle: "y")
        #expect(item.style == .destructive)
        #expect(item.tracked == true)
        #expect(item.actions.count == 1)
        #expect(item.actions[0].kind == .destructive)
        #expect(item.actions[0].title == "OK")
    }

    @Test(".alert produces an untracked destructive item")
    func alert_singleArg_destructiveStyleUntracked() {
        let item = DialogItem.alert(title: "x", subtitle: "y")
        #expect(item.style == .destructive)
        #expect(item.tracked == false)
        #expect(item.actions.count == 1)
        #expect(item.actions[0].kind == .destructive)
    }

    @Test(".info produces an untracked standard-style item")
    func info_singleArg_standardStyleUntracked() {
        let item = DialogItem.info(title: "x", subtitle: "y")
        #expect(item.style == .standard)
        #expect(item.tracked == false)
        #expect(item.actions.count == 1)
        #expect(item.actions[0].kind == .standard)
    }

    @Test(".error accepts a custom action builder block")
    func error_customActions_overridesDefault() {
        let item = DialogItem.error(title: "x", subtitle: "y") {
            .destructive("A", action: {});
            .cancel()
        }
        #expect(item.actions.count == 2)
        #expect(item.actions[0].title == "A")
        #expect(item.actions[1].title == "Cancel")
    }

    @Test(".success produces an untracked success-style item that is not dismissable by default")
    func success_defaults_untrackedNonDismissable() {
        let item = DialogItem.success(title: "x", subtitle: "y")
        #expect(item.style == .success)
        #expect(item.tracked == false)
        #expect(item.dismissable == false)
    }

    @Test("dismissable parameter overrides the factory default")
    func dismissable_parameter_overridesDefault() {
        let nonDismissableError = DialogItem.error(title: "x", subtitle: "y", dismissable: false)
        #expect(nonDismissableError.dismissable == false)

        let dismissableSuccess = DialogItem.success(title: "x", subtitle: "y", dismissable: true)
        #expect(dismissableSuccess.dismissable == true)
    }

    @Test(
        ".contactsOnFlipcash pluralizes Contact/Contacts by count",
        arguments: [
            (1, "1 Contact Already On Flipcash"),
            (2, "2 Contacts Already On Flipcash"),
        ]
    )
    func contactsOnFlipcash_pluralizesTitle(count: Int, expectedTitle: String) {
        let item = DialogItem.contactsOnFlipcash(count: count)
        #expect(item.title == expectedTitle)
        #expect(item.style == .standard)
    }

    @Test("Factories have no checkbox")
    func factories_noCheckbox() {
        #expect(DialogItem.error(title: "x", subtitle: "y").checkbox == nil)
        #expect(DialogItem.alert(title: "x", subtitle: "y").checkbox == nil)
        #expect(DialogItem.info(title: "x", subtitle: "y").checkbox == nil)
        #expect(DialogItem.success(title: "x", subtitle: "y").checkbox == nil)
    }

    @Test(".checkbox adds a label and keeps the rest of the item")
    func checkbox_keepsItem() {
        var dismissed = false
        let item = DialogItem.info(title: "x", subtitle: "y") {
            .standard("A", action: {});
            .cancel()
        }
        .onDismiss { dismissed = true }
        .checkbox("Tick")
        #expect(item.checkbox?.label == "Tick")
        #expect(item.title == "x")
        #expect(item.actions.map(\.title) == ["A", "Cancel"])
        item.onDismiss?()
        #expect(dismissed)
    }

    @Test(".onDismiss keeps the checkbox")
    func onDismiss_keepsCheckbox() {
        let item = DialogItem.info(title: "x", subtitle: "y").checkbox("Tick").onDismiss {}
        #expect(item.checkbox?.label == "Tick")
    }

    @Test("A checked action receives the checkbox state; a plain one ignores it")
    func perform_passesCheckedState() {
        var received: Bool?
        var plainRan = false
        DialogAction.standard("A", checked: { received = $0 }).perform(isChecked: true)
        DialogAction.standard("B", action: { plainRan = true }).perform(isChecked: true)
        #expect(received == true)
        #expect(plainRan)
    }
}
