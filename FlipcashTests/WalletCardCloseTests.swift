//
//  WalletCardCloseTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

/// What the wallet tab shows in the step that removes a closing card's page.
@Suite("Wallet card close") @MainActor
struct WalletCardCloseTests {

    // A deep-linked card opens with the Money content faded out. If it fades
    // back in only after the page is removed, one frame shows neither.
    @Test("Money is back at full opacity in the step that removes the page")
    func moneyRestoresBeforePageGoes() {
        #expect(WalletLayout.money.restoresContentWhenCardCloses)
    }

    @Test("Today's wallet still fades its deck in as the card travels home")
    func standardKeepsItsFade() {
        #expect(!WalletLayout.standard.restoresContentWhenCardCloses)
    }
}
