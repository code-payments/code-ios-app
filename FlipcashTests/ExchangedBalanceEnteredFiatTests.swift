//
//  ExchangedBalanceEnteredFiatTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("ExchangedBalance.enteredFiat")
struct ExchangedBalanceEnteredFiatTests {

    @Test("Non-positive amount returns nil")
    func nonPositiveAmount_returnsNil() {
        let balance = ExchangedBalance.makeTest(mint: .usdf, quarks: 100_000_000)
        #expect(balance.enteredFiat(for: 0, rate: .oneToOne) == nil)
        #expect(balance.enteredFiat(for: -5, rate: .oneToOne) == nil)
    }

    @Test("USDF entry maps straight through to a USDF amount")
    func usdf_mapsThrough() throws {
        let balance = ExchangedBalance.makeTest(mint: .usdf, quarks: 100_000_000)
        let fiat = try #require(balance.enteredFiat(for: 10.50, rate: .oneToOne))
        #expect(fiat.mint == .usdf)
        #expect(fiat.nativeAmount.value == 10.50)
    }

    @Test("Bonded entry within TVL prices via the curve, not the sentinel")
    func bonded_withinTVL_pricesViaCurve() throws {
        let balance = ExchangedBalance.makeTest(
            mint: .jeffy,
            quarks: 1_000_000_000_000,
            supplyQuarks: 10_000 * 10_000_000_000
        )
        let fiat = try #require(balance.enteredFiat(for: 1.00, rate: .oneToOne))
        #expect(fiat.mint == .jeffy)
        #expect(fiat.onChainAmount.quarks > 0)
        #expect(fiat.onChainAmount.quarks != balance.stored.quarks + 1)
    }

    @Test("Bonded entry beyond curve TVL returns the over-balance sentinel")
    func bonded_beyondTVL_returnsSentinel() throws {
        let balance = ExchangedBalance.makeTest(
            mint: .jeffy,
            quarks: 10 * 10_000_000_000,
            supplyQuarks: 10_000 * 10_000_000_000
        )
        // Far beyond what a 10,000-token curve can price — forces the sentinel.
        let fiat = try #require(balance.enteredFiat(for: 1_000_000_000_000_000, rate: .oneToOne))
        #expect(fiat.onChainAmount.quarks == balance.stored.quarks + 1)
    }
}
