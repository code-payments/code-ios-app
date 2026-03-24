//
//  StoredBalanceAppreciationTests.swift
//  FlipcashTests
//
//  Created by Claude on 2026-03-24.
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@Suite("StoredBalance - Appreciation")
struct StoredBalanceAppreciationTests {

    // MARK: - Helpers

    /// Creates a USDF `StoredBalance` with the given quarks and cost basis.
    /// USDF balances don't use a bonding curve, so `usdf` equals the raw quarks.
    private func makeUSDFBalance(quarks: UInt64, costBasis: Double) throws -> StoredBalance {
        try StoredBalance(
            quarks: quarks,
            symbol: "USDF",
            name: "USDF Coin",
            supplyFromBonding: nil,
            sellFeeBps: nil,
            mint: .usdf,
            vmAuthority: nil,
            updatedAt: Date(),
            imageURL: nil,
            costBasis: costBasis
        )
    }

    @Test("Positive appreciation when value exceeds cost basis")
    func positiveAppreciation() throws {
        // 10 USDF (6 decimals) with $5 cost basis → $5 appreciation
        let balance = try makeUSDFBalance(quarks: 10_000_000, costBasis: 5.0)
        let (value, isPositive) = balance.computeAppreciation(with: .oneToOne)

        #expect(isPositive == true)
        #expect(value.converted.quarks == 5_000_000)
    }

    @Test("Negative appreciation when cost basis exceeds value")
    func negativeAppreciation() throws {
        // 3 USDF with $5 cost basis → -$2 depreciation
        let balance = try makeUSDFBalance(quarks: 3_000_000, costBasis: 5.0)
        let (value, isPositive) = balance.computeAppreciation(with: .oneToOne)

        #expect(isPositive == false)
        #expect(value.converted.quarks == 2_000_000)
    }

    @Test("Zero appreciation when value equals cost basis")
    func zeroAppreciation() throws {
        let balance = try makeUSDFBalance(quarks: 5_000_000, costBasis: 5.0)
        let (value, isPositive) = balance.computeAppreciation(with: .oneToOne)

        #expect(isPositive == true, "Zero appreciation is treated as positive")
        #expect(value.converted.quarks == 0)
    }

    @Test("Zero cost basis treats entire value as appreciation")
    func zeroCostBasis() throws {
        let balance = try makeUSDFBalance(quarks: 7_000_000, costBasis: 0)
        let (value, isPositive) = balance.computeAppreciation(with: .oneToOne)

        #expect(isPositive == true)
        #expect(value.converted.quarks == 7_000_000)
    }

    @Test("Zero balance reports entire cost basis as depreciation")
    func zeroBalanceWithCostBasis() throws {
        let balance = try makeUSDFBalance(quarks: 0, costBasis: 10.0)
        let (value, isPositive) = balance.computeAppreciation(with: .oneToOne)

        #expect(isPositive == false)
        #expect(value.converted.quarks == 10_000_000)
    }

    @Test("Zero balance with zero cost basis shows no appreciation")
    func zeroBalanceZeroCostBasis() throws {
        let balance = try makeUSDFBalance(quarks: 0, costBasis: 0)
        let (value, isPositive) = balance.computeAppreciation(with: .oneToOne)

        #expect(isPositive == true)
        #expect(value.converted.quarks == 0)
    }

    @Test("Appreciation converts correctly with non-USD rate")
    func nonUSDRateConversion() throws {
        // 10 USDF with $5 cost basis → $5 USD appreciation → $7 CAD at 1.4x
        let balance = try makeUSDFBalance(quarks: 10_000_000, costBasis: 5.0)
        let cadRate = Rate(fx: 1.4, currency: .cad)
        let (value, isPositive) = balance.computeAppreciation(with: cadRate)

        #expect(isPositive == true)
        #expect(value.converted.quarks == 7_000_000)
    }
}
