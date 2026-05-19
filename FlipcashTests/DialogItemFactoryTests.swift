//
//  DialogItemFactoryTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashUI

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
}
