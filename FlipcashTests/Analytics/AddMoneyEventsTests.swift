//
//  AddMoneyEventsTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

@MainActor
@Suite("Add Money funnel contract — names shared verbatim with Android")
struct AddMoneyEventsTests {

    @Test("Event names match the Android funnel")
    func eventNames_matchAndroid() {
        #expect(Analytics.AddMoneyEvent.opened.eventName == "Add Money: Opened")
        #expect(Analytics.AddMoneyEvent.methodSelected.eventName == "Add Money: Method Selected")
        #expect(Analytics.AddMoneyEvent.amountConfirmed.eventName == "Add Money: Amount Confirmed")
        #expect(Analytics.AddMoneyEvent.paymentInvoked.eventName == "Add Money: Payment Invoked")
        #expect(Analytics.AddMoneyEvent.addressCopied.eventName == "Add Money: Address Copied")
        #expect(Analytics.AddMoneyEvent.terminal.eventName == "Add Money")
    }

    @Test("Property keys have the expected raw values")
    func propertyKeys_rawValues_areExpected() {
        #expect(Analytics.Property.source.rawValue == "Source")
        #expect(Analytics.Property.method.rawValue == "Method")
        #expect(Analytics.Property.state.rawValue == "State")
        #expect(Analytics.Property.mint.rawValue == "Mint")
    }

    @Test("Source values match the Android funnel")
    func sourceValues_matchAndroid() {
        #expect(Analytics.AddMoneySource.menu.rawValue == "Menu")
        #expect(Analytics.AddMoneySource.giveShortfall.rawValue == "Give Shortfall")
        #expect(Analytics.AddMoneySource.buyShortfall.rawValue == "Buy Shortfall")
        #expect(Analytics.AddMoneySource.chat.rawValue == "Chat")
        #expect(Analytics.AddMoneySource.scanner.rawValue == "Scanner")
        #expect(Analytics.AddMoneySource.balance.rawValue == "Balance")
    }

    @Test("Method values match the Android funnel")
    func methodValues_matchAndroid() {
        #expect(DepositMethod.coinbase.analyticsValue == "Coinbase")
        #expect(DepositMethod.phantom.analyticsValue == "Phantom")
        #expect(DepositMethod.otherWallet.analyticsValue == "Other Wallet")
    }
}
