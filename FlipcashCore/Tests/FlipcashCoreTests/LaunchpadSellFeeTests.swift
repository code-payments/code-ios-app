//
//  LaunchpadSellFeeTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("Launchpad sell fee math")
struct LaunchpadSellFeeTests {

    @Test("Fee is bps of the on-chain amount with native scaled by the actual ratio")
    func launchpadSellFee_basic() {
        let gross = ExchangedFiat(nativeAmount: FiatAmount.usd(20.20), rate: .oneToOne)

        let fee = gross.launchpadSellFee(bps: 100)

        #expect(fee.onChainAmount.quarks == gross.onChainAmount.quarks / 100)
        #expect(fee.nativeAmount.formatted() == "$0.20")
    }

    @Test("A fee that rounds to 0 quarks also displays as 0 fiat")
    func launchpadSellFee_zeroQuarks() {
        let tiny = ExchangedFiat(
            onChainAmount: TokenAmount(quarks: 50, mint: .usdf),
            nativeAmount: FiatAmount.usd(0.00005),
            currencyRate: .oneToOne
        )

        let fee = tiny.launchpadSellFee(bps: 100)

        #expect(fee.onChainAmount.quarks == 0)
        #expect(fee.nativeAmount.value == 0)
    }

    @Test("Grossing up nets back to the original after the fee", arguments: [
        (net: Decimal(20), grossFormatted: "$20.20"),
        (net: Decimal(10), grossFormatted: "$10.10"),
        (net: Decimal(string: "0.01")!, grossFormatted: "$0.01"),
    ])
    func grossingUp_roundTrip(net: Decimal, grossFormatted: String) {
        let gross = FiatAmount.usd(net).grossingUpLaunchpadSellFee(bps: 100)

        #expect(gross.formatted() == grossFormatted)

        // net = gross × (1 − f): the displayed pair must be self-consistent.
        let grossExchanged = ExchangedFiat(nativeAmount: gross, rate: .oneToOne)
        let netted = grossExchanged.subtractingFee(grossExchanged.launchpadSellFee(bps: 100).onChainAmount)
        #expect(netted.nativeAmount.value.rounded(to: 2) == net.rounded(to: 2))
    }

    @Test("Buy Maximum shape: full balance nets to balance × (1 − f)")
    func buyMaximum_netting() {
        let balance = ExchangedFiat(nativeAmount: FiatAmount.usd(20), rate: .oneToOne)

        let fee = balance.launchpadSellFee(bps: 100)
        let net = balance.subtractingFee(fee.onChainAmount)

        #expect(fee.nativeAmount.formatted() == "$0.20")
        #expect(net.nativeAmount.formatted() == "$19.80")
    }

    @Test("Fee math stays exact at the max launchpad supply — quarks × bps would overflow UInt64")
    func launchpadSellFee_maxSupply_noOverflow() {
        // 21M tokens at 10 decimals: a naive quarks × 100 exceeds UInt64.max.
        let maxSupplyQuarks: UInt64 = 21_000_000 * 10_000_000_000
        let holding = ExchangedFiat(
            onChainAmount: TokenAmount(quarks: maxSupplyQuarks, mint: .usdf),
            nativeAmount: FiatAmount.usd(1),
            currencyRate: .oneToOne
        )

        let fee = holding.launchpadSellFee(bps: 100)

        #expect(fee.onChainAmount.quarks == 2_100_000_000_000_000)
    }

    @Test("Grossing up a 100% fee returns the amount unchanged instead of dividing by zero")
    func grossingUp_fullFeeBps_returnsSelf() {
        let net = FiatAmount.usd(20)

        #expect(net.grossingUpLaunchpadSellFee(bps: 10_000) == net)
    }
}
