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

    @Test("Selling the whole balance nets to balance × (1 − f)")
    func wholeBalance_netting() {
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

    // MARK: - Inverses: the most a balance can fund

    @Test("Spendable under a grossed-up fee grosses back up to exactly the balance")
    func spendableUnderGrossedUp_roundTrips() {
        let balance = FiatAmount.usd(20)

        let spendable = balance.spendableUnderGrossedUpSellFee(bps: 100)

        #expect(spendable.formatted() == "$19.80")
        #expect(spendable.grossingUpLaunchpadSellFee(bps: 100).value.rounded(to: 2) == balance.value)
    }

    @Test("Spendable under a fee charged on top leaves exactly enough for that fee")
    func spendableUnderOnTop_leavesRoomForTheFee() {
        let balance = FiatAmount.usd(Decimal(string: "10.10")!)

        let spendable = balance.spendableUnderSellFeeOnTop(bps: 100)

        #expect(spendable.formatted() == "$10.00")
        // entry + its own fee lands back on the balance.
        let debit = ExchangedFiat(nativeAmount: spendable, rate: .oneToOne)
        #expect((spendable + debit.launchpadSellFee(bps: 100).nativeAmount).value.rounded(to: 2) == balance.value)
    }

    @Test("Spending the whole balance is only possible with a zero fee")
    func spendable_zeroBps_isTheWholeBalance() {
        let balance = FiatAmount.usd(20)

        #expect(balance.spendableUnderSellFeeOnTop(bps: 0) == balance)
        #expect(balance.spendableUnderGrossedUpSellFee(bps: 0) == balance)
    }

    @Test("An on-top fee above 100% is clamped rather than over-shrinking the entry")
    func spendableUnderOnTop_bpsAboveMax_isClamped() {
        let balance = FiatAmount.usd(20)

        // Clamped to 10_000 (100%): half the balance covers a fee equal to the entry.
        #expect(balance.spendableUnderSellFeeOnTop(bps: 12_000).formatted() == "$10.00")
    }
}
