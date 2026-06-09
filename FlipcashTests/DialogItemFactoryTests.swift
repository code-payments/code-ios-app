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

    @Test(".noGiveableBalance uses the deposit-funds design")
    func noGiveableBalance_depositDesign() {
        let item = DialogItem.noGiveableBalance(onDeposit: {})
        #expect(item.title == "No Balance Yet")
        #expect(item.subtitle == "Deposit funds to give cash")
        #expect(item.style == .standard)
        #expect(item.actions.count == 2)
        #expect(item.actions[0].title == "Deposit Funds")
        #expect(item.actions[0].kind == .standard)
        #expect(item.actions[1].title == "Cancel")
        #expect(item.actions[1].kind == .subtle)
    }
}
