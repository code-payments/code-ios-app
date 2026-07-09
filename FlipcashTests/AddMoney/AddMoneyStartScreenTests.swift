//
//  AddMoneyStartScreenTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash

@Suite("AddMoneyStartScreen — method visibility & copy")
@MainActor
struct AddMoneyStartScreenTests {

    @Test("Coinbase (Pay) shows only when the onramp is available")
    func visibleMethods_honorsCoinbaseOnramp() {
        #expect(
            AddMoneyStartScreen.visibleMethods(hasCoinbaseOnramp: true)
                == [.coinbase, .phantom, .otherWallet]
        )
        #expect(
            AddMoneyStartScreen.visibleMethods(hasCoinbaseOnramp: false)
                == [.phantom, .otherWallet]
        )
    }

    @Test("The No Balance Yet subtitle is driven by the context")
    func noBalanceSubtitle_matchesContext() {
        #expect(AddMoneyContext.buyCurrency.noBalanceSubtitle == "Add money to buy currencies")
        #expect(AddMoneyContext.createCurrency.noBalanceSubtitle == "Add money to create a currency")
    }
}
