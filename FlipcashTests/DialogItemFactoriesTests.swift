//
//  DialogItemFactoriesTests.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-05-12.
//

import Foundation
import Testing
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("DialogItem factories")
struct DialogItemFactoriesTests {

    // MARK: - noGiveableBalance

    @Test("noGiveableBalance dialog uses the standard (non-destructive) style")
    func noGiveableBalance_usesStandardStyle() {
        let dialog = DialogItem.noGiveableBalance(onDiscover: {})
        #expect(dialog.style == .standard)
    }

    @Test("noGiveableBalance dialog title and subtitle match the wording shown to users with no giveable balance")
    func noGiveableBalance_copy() {
        let dialog = DialogItem.noGiveableBalance(onDiscover: {})
        #expect(dialog.title == "No Balance Yet")
        #expect(dialog.subtitle == "Buy a currency to get started, or get another Flipcash user to give you some cash")
    }

    @Test("noGiveableBalance exposes a primary Discover CTA above a subtle Cancel")
    func noGiveableBalance_actionLayout() throws {
        let dialog = DialogItem.noGiveableBalance(onDiscover: {})

        try #require(dialog.actions.count == 2)
        #expect(dialog.actions[0].title == "Discover Currencies")
        #expect(dialog.actions[0].kind == .standard)
        #expect(dialog.actions[1].title == "Cancel")
        #expect(dialog.actions[1].kind == .subtle)
    }

    @Test("Tapping Discover fires the supplied onDiscover closure")
    func noGiveableBalance_discoverActionFires() throws {
        var fired = false
        let dialog = DialogItem.noGiveableBalance(onDiscover: { fired = true })

        let discoverAction = try #require(dialog.actions.first { $0.title == "Discover Currencies" })
        discoverAction.action()

        #expect(fired)
    }

    // MARK: - applePaySheetTimeout

    @Test("applePaySheetTimeout dialog uses the standard (informational) style")
    func applePaySheetTimeout_usesStandardStyle() {
        let dialog = DialogItem.applePaySheetTimeout
        #expect(dialog.style == .standard)
    }

    @Test("applePaySheetTimeout dialog title and subtitle match the wording shown when the Apple Pay sheet times out")
    func applePaySheetTimeout_copy() {
        let dialog = DialogItem.applePaySheetTimeout
        #expect(dialog.title == "Purchase Timed Out")
        #expect(dialog.subtitle == "Purchases must be authorized within 60 seconds")
    }

    @Test("applePaySheetTimeout exposes a single OK action")
    func applePaySheetTimeout_actionLayout() throws {
        let dialog = DialogItem.applePaySheetTimeout

        try #require(dialog.actions.count == 1)
        #expect(dialog.actions[0].title == "OK")
        #expect(dialog.actions[0].kind == .standard)
    }
}
