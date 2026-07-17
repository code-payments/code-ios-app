//
//  LaunchPaymentSplitTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("LaunchPaymentSplit")
struct LaunchPaymentSplitTests {

    // Supply chosen so ~2000 tokens ≈ $20 of curve value (matches the buy tests).
    private static let supply: UInt64 = 50_000 * 10_000_000_000
    private static let ampleBalance = FiatAmount.usd(1_000)

    @Test("The summed legs value to exactly the fixed USD total")
    func totalNativeIsExact() throws {
        let split = try #require(LaunchPaymentSplit.compute(
            purchaseUSD: 10, feeUSD: 10, rate: .oneToOne, paymentMint: .jeffy,
            supplyQuarks: Self.supply, balanceUSD: Self.ampleBalance
        ))
        // The wire's full-amount valuation is the sum of the legs; the server
        // rejects anything but exactly $20.00 (a float `!=` compare).
        let total = split.swap.adding(split.fee)

        #expect(total.nativeAmount == FiatAmount.usd(20))
        #expect(total.nativeAmount.doubleValue == 20.0)
    }

    @Test("Fee quarks re-value to ~the fee USD within a half cent")
    func feeQuarksValueWithinTolerance() throws {
        let split = try #require(LaunchPaymentSplit.compute(
            purchaseUSD: 10, feeUSD: 10, rate: .oneToOne, paymentMint: .jeffy,
            supplyQuarks: Self.supply, balanceUSD: Self.ampleBalance
        ))
        // Re-value the fee quarks the way the server does (curve sell, feeBps 0).
        let revalued = ExchangedFiat.compute(
            onChainAmount: split.fee.onChainAmount, rate: .oneToOne, supplyQuarks: Self.supply
        )
        let delta = (revalued.nativeAmount.value - 10 as Decimal).magnitude
        #expect(delta <= Decimal(string: "0.005")!)
    }

    @Test("The total leg is capped to the balance's USD value")
    func totalCapsToBalance() throws {
        let cappedUSD = FiatAmount.usd(12)
        let split = try #require(LaunchPaymentSplit.compute(
            purchaseUSD: 10, feeUSD: 10, rate: .oneToOne, paymentMint: .jeffy,
            supplyQuarks: Self.supply, balanceUSD: cappedUSD
        ))
        let total = split.swap.onChainAmount.quarks + split.fee.onChainAmount.quarks

        let expectedCapped = try #require(ExchangedFiat.compute(
            fromEntered: .usd(12), rate: .oneToOne, mint: .jeffy, supplyQuarks: Self.supply
        )).onChainAmount.quarks
        #expect(total == expectedCapped)
    }

    @Test("A balance displaying $20.00 seats the capped split inside the server's ±half-cent window", arguments: [
        UInt64(50_000) * 10_000_000_000,
        UInt64(5_000_000) * 10_000_000_000, // deeper on the curve — nonlinear region
    ])
    func boundaryBalanceStaysInWindow(supply: UInt64) throws {
        // Raw value $19.996 rounds to a displayed $20.00 — eligible by rule 5.
        let boundary = try #require(ExchangedFiat.compute(
            fromEntered: .usd(Decimal(string: "19.996")!),
            rate: .oneToOne, mint: .jeffy, supplyQuarks: supply
        ))
        let balanceUSD = ExchangedFiat.compute(
            onChainAmount: boundary.onChainAmount, rate: .oneToOne, supplyQuarks: supply
        ).nativeAmount

        let split = try #require(LaunchPaymentSplit.compute(
            purchaseUSD: 10, feeUSD: 10, rate: .oneToOne, paymentMint: .jeffy,
            supplyQuarks: supply, balanceUSD: balanceUSD
        ))

        // Capped total never exceeds the holding, yet still re-values (the way
        // the server does) within ±$0.005 of the exact $20 the wire declares.
        let totalQuarks = split.swap.onChainAmount.quarks + split.fee.onChainAmount.quarks
        #expect(totalQuarks <= boundary.onChainAmount.quarks)

        let revalued = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: totalQuarks, mint: .jeffy),
            rate: .oneToOne, supplyQuarks: supply
        )
        let delta = (revalued.nativeAmount.value - 20 as Decimal).magnitude
        #expect(delta <= Decimal(string: "0.005")!)
    }
}
