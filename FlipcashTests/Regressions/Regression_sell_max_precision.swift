//
//  Regression_sell_max_precision.swift
//  Flipcash
//
//  Invariant: `StoredBalance.usdf.decimalValue` must never exceed the
//  bonding curve's exact BigDecimal TVL. Violating the invariant causes
//  the sell-max Next button to be disabled on newly-minted currencies.
//

import Foundation
import Testing
@preconcurrency import BigDecimal
import FlipcashCore
@testable import Flipcash

@Suite("Regression: sell-max precision (newly-minted bonding-curve balance)")
struct Regression_sell_max_precision {

    private let curve = DiscreteBondingCurve()
    private let mint: PublicKey = .jeffy
    private let rate: Rate = .oneToOne

    private func makeStoredBalance(supply: UInt64) throws -> StoredBalance {
        try StoredBalance(
            quarks: supply,
            symbol: "TEST",
            name: "Test",
            supplyFromBonding: supply,
            sellFeeBps: 0,
            mint: mint,
            vmAuthority: nil,
            updatedAt: Date(),
            imageURL: nil,
            costBasis: 0
        )
    }

    /// Sample supplies spanning the early curve. Roughly half of these
    /// historically triggered the HALF-UP overshoot before the floor fix —
    /// enough for any regression of the rounding direction to be detected
    /// by at least one element without looping over thousands of values.
    static let sampledSupplies: [Int] = [
        1_013, 2_357, 5_821, 12_347, 37_739, 71_993, 150_001
    ]

    @Test(
        "StoredBalance.usdf never exceeds the bonding curve's exact TVL",
        arguments: sampledSupplies
    )
    func storedBalanceUsdf_doesNotOvershootCurveTVL(tokens: Int) throws {
        let supply = UInt64(tokens) * UInt64(DiscreteBondingCurve.quarksPerToken)
        let sell = try #require(
            curve.sell(tokenQuarks: Int(supply), feeBps: 0, supplyQuarks: Int(supply))
        )
        let stored = try makeStoredBalance(supply: supply)

        let usdf: Foundation.Decimal = stored.usdf.decimalValue
        let tvl: Foundation.Decimal = sell.netUSDF.asDecimal()

        #expect(usdf <= tvl)
    }

    @Test("Selling a fresh currency after a $100 buy does not return nil")
    func computeFromEntered_afterFreshHundredDollarBuy_returnsNonNil() throws {
        // Fresh currency + $100 buy is the concrete repro the user reported
        // as "100% of the time". Sell the exact stored balance and expect
        // a non-nil ExchangedFiat.
        let buyEstimate = try #require(
            curve.buy(
                usdcQuarks: 100_000_000, // $100 USDF in 6-decimal quarks
                feeBps: 0,
                supplyQuarks: 0
            ),
            "Curve failed to price a $100 buy on a fresh currency"
        )

        // Server-side semantics: tokens from the buy, scaled to quarks and
        // truncated toward zero (cannot mint a fractional quark).
        let supplyQuarks = try #require(
            Int(
                buyEstimate.netTokens
                    .multiply(BigDecimal(DiscreteBondingCurve.quarksPerToken), DiscreteBondingCurve.rounding)
                    .round(Rounding(.towardZero, 0))
                    .asString(.plain)
            ),
            "Failed to scale $100 buy tokens into integer quarks"
        )

        let stored = try makeStoredBalance(supply: UInt64(supplyQuarks))

        let entered = ExchangedFiat.computeFromEntered(
            amount: stored.usdf.decimalValue,
            rate: rate,
            mint: mint,
            supplyQuarks: UInt64(supplyQuarks),
            balance: stored.usdf,
            tokenBalanceQuarks: stored.quarks
        )

        #expect(
            entered != nil,
            "selling exactly the stored balance after a $100 fresh-currency buy must succeed"
        )
    }
}
