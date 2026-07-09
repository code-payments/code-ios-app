//
//  AddMoneyContextTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

@Suite("AddMoneyContext")
struct AddMoneyContextTests {

    @Test("Buy context uses the buy-currencies subtitle")
    func buySubtitle() {
        #expect(AddMoneyContext.buyCurrency.noBalanceSubtitle == "Add money to buy currencies")
    }

    @Test("Launch context uses the create-a-currency subtitle")
    func launchSubtitle() {
        #expect(AddMoneyContext.createCurrency.noBalanceSubtitle == "Add money to create a currency")
    }

    @Test("Give-cash context uses the give-cash subtitle")
    func giveCashSubtitle() {
        #expect(AddMoneyContext.giveCash.noBalanceSubtitle == "Add money to give cash")
    }
}
