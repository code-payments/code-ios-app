//
//  AddMoneyEventsTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

@MainActor
@Suite("Add Money funnel contract — names shared verbatim with Android", .serialized)
struct AddMoneyEventsTests {

    @Test("Method values match the Android funnel", arguments: [
        (DepositMethod.coinbase, "Coinbase"),
        (.phantom, "Phantom"),
        (.otherWallet, "Other Wallet"),
    ])
    func methodValues_matchAndroid(_ method: DepositMethod, _ expected: String) throws {
        let event = try Analytics.recordingSends { Analytics.addMoneyMethodSelected(method: method) }.single
        #expect(event.name == "Add Money: Method Selected")
        #expect(event.properties["Method"] as? String == expected)
    }
}
