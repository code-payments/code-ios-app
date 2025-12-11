//
//  CurrencyInfoScreenTests.swift
//  FlipcashTests
//
//  Created by Claude on 2025-12-11.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// Tests for CurrencyInfoScreen market cap calculation logic
/// These tests verify the DiscreteBondingCurve.marketCap() → ExchangedFiat pipeline
/// that CurrencyInfoScreen uses to display market cap values.
///
/// Note: marketCap(for:) takes supplyQuarks (supply × 10^10), while spotPrice(at:) takes supply in whole tokens.
@Suite("CurrencyInfoScreen - Market Cap Integration")
struct CurrencyInfoScreenTests {

    let curve = DiscreteBondingCurve()

    // quarksPerToken = 10^10 (token has 10 decimals)
    let quarksPerToken = DiscreteBondingCurve.quarksPerToken

    // MARK: - Market Cap Calculation Tests

    @Test("Market cap at zero supply returns zero")
    func marketCapAtZeroSupply() {
        let supplyQuarks = 0
        let mCap = curve.marketCap(for: supplyQuarks)

        #expect(mCap == 0, "Market cap at zero supply should be zero")
    }

    @Test("Market cap at 1000 tokens is positive")
    func marketCapAt1000Tokens() {
        // 1000 tokens in quarks (10 decimals)
        let supplyQuarks = 1000 * quarksPerToken
        let mCap = curve.marketCap(for: supplyQuarks)

        #expect(mCap != nil, "Market cap should not be nil")
        if let mCap = mCap {
            #expect(mCap > 0, "Market cap should be positive")
            // At early supply (~$0.01/token), 1000 tokens ≈ $10 market cap
            #expect(mCap > 5, "Market cap should be at least $5")
            #expect(mCap < 20, "Market cap should be less than $20")
        }
    }

    @Test("Market cap at 100,000 tokens is substantial")
    func marketCapAt100KTokens() {
        let supplyQuarks = 100_000 * quarksPerToken
        let mCap = curve.marketCap(for: supplyQuarks)

        #expect(mCap != nil)
        if let mCap = mCap {
            #expect(mCap > 1000, "100K tokens should have >$1000 market cap")
        }
    }

    @Test("Market cap can be converted to ExchangedFiat")
    func marketCapToExchangedFiat() throws {
        // Simulate what CurrencyInfoScreen does
        let supplyQuarks = 10_000 * quarksPerToken
        guard let mCap = curve.marketCap(for: supplyQuarks) else {
            Issue.record("Market cap should not be nil")
            return
        }

        // Convert to Quarks (using USDC decimals = 6)
        let usdc = try Quarks(
            fiatDecimal: mCap,
            currencyCode: .usd,
            decimals: 6  // USDC decimals
        )

        // Convert to ExchangedFiat
        let exchanged = try ExchangedFiat(
            underlying: usdc,
            rate: .oneToOne,  // 1:1 rate for USD
            mint: .usdc
        )

        #expect(exchanged.converted.quarks > 0, "Converted quarks should be positive")
        #expect(exchanged.underlying.quarks > 0, "Underlying quarks should be positive")
    }

    @Test("Market cap with non-USD rate converts correctly")
    func marketCapWithNonUSDRate() throws {
        let supplyQuarks = 10_000 * quarksPerToken
        guard let mCap = curve.marketCap(for: supplyQuarks) else {
            Issue.record("Market cap should not be nil")
            return
        }

        // USD value
        let usdQuarks = try Quarks(
            fiatDecimal: mCap,
            currencyCode: .usd,
            decimals: 6
        )
        let usdExchanged = try ExchangedFiat(
            underlying: usdQuarks,
            rate: .oneToOne,
            mint: .usdc
        )

        // CAD value (1.4x rate)
        let cadRate = Rate(fx: 1.4, currency: .cad)
        let cadExchanged = try ExchangedFiat(
            underlying: usdQuarks,
            rate: cadRate,
            mint: .usdc
        )

        // CAD converted value should be ~1.4x USD
        let ratio = Decimal(cadExchanged.converted.quarks) / Decimal(usdExchanged.converted.quarks)
        #expect(ratio > 1.35 && ratio < 1.45, "CAD should be ~1.4x USD")
    }

    // MARK: - Supply Edge Cases

    @Test("Market cap at max supply returns value")
    func marketCapAtMaxSupply() {
        // maxSupply is in whole tokens (21M), convert to quarks
        let supplyQuarks = DiscreteBondingCurve.maxSupply * quarksPerToken
        let mCap = curve.marketCap(for: supplyQuarks)

        #expect(mCap != nil, "Market cap at max supply should not be nil")
        if let mCap = mCap {
            #expect(mCap > 0, "Market cap at max supply should be positive")
        }
    }

    @Test("Market cap just over max supply returns nil")
    func marketCapOverMaxSupply() {
        // Supply beyond max (21M + 1 tokens) in quarks
        let supplyQuarks = (DiscreteBondingCurve.maxSupply + 1) * quarksPerToken
        let mCap = curve.marketCap(for: supplyQuarks)

        #expect(mCap == nil, "Market cap over max supply should be nil")
    }

    @Test("Market cap with nil supplyFromBonding defaults to zero")
    func marketCapWithNilSupply() {
        // Simulates CurrencyInfoScreen behavior when supplyFromBonding is nil
        var supply: Int = 0
        let supplyFromBonding: UInt64? = nil

        if let supplyFromBonding = supplyFromBonding {
            supply = Int(supplyFromBonding)
        }

        let mCap = curve.marketCap(for: supply)
        #expect(mCap == 0, "Nil supply should result in zero market cap")
    }

    // MARK: - Consistency Tests

    @Test("Market cap equals supply times spot price")
    func marketCapEqualsSupplyTimesSpotPrice() {
        // For several supply values, verify marketCap = supply × spotPrice
        // Note: marketCap takes quarks, spotPrice takes whole tokens
        let testSupplies = [100, 1000, 10_000, 100_000]

        for supplyTokens in testSupplies {
            let supplyQuarks = supplyTokens * quarksPerToken

            guard let mCap = curve.marketCap(for: supplyQuarks),
                  let spotPrice = curve.spotPrice(at: supplyTokens) else {
                Issue.record("Failed to get market cap or spot price for supply \(supplyTokens)")
                continue
            }

            // Calculate expected market cap: supplyTokens × spotPrice
            let expectedMCap = Decimal(supplyTokens) * spotPrice.asDecimal()

            // Allow small tolerance for BigDecimal conversion
            let actualMCap = Decimal(string: mCap.description) ?? 0
            let diff = abs(expectedMCap - actualMCap)
            let tolerance = expectedMCap * 0.001  // 0.1% tolerance

            #expect(diff < tolerance,
                   "Market cap at supply \(supplyTokens) should equal supply × spotPrice. Expected ~\(expectedMCap), got \(actualMCap)")
        }
    }

    @Test("Market cap increases with supply")
    func marketCapIncreasesWithSupply() {
        var previousMCap: Decimal = 0

        for supplyTokens in [100, 1000, 5000, 10_000, 50_000, 100_000] {
            let supplyQuarks = supplyTokens * quarksPerToken
            guard let mCap = curve.marketCap(for: supplyQuarks) else {
                Issue.record("Market cap should not be nil for supply \(supplyTokens)")
                continue
            }

            #expect(mCap > previousMCap,
                   "Market cap should increase: supply \(supplyTokens) should have greater market cap than previous")
            previousMCap = mCap
        }
    }
}
