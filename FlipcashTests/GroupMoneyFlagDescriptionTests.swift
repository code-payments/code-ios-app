//
//  GroupMoneyFlagDescriptionTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

@Suite("Group Money flag description") @MainActor
struct GroupMoneyFlagDescriptionTests {

    // The toggle is listed for staff and for any device unlocked with the
    // version easter egg (`BetaFlags.developerOptions`), so the description
    // names both rather than staff alone.
    @Test("Names both staff accounts and unlocked devices as who gets it")
    func namesWhoGetsIt() {
        #expect(BetaFlags.Option.groupMoneyUI.localizedDescription == "If enabled, staff accounts and unlocked devices get Groups and Money in place of the home tabs.")
    }
}
