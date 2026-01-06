//
//  ExchangedFiatTests.swift
//  Code
//
//  Created by Dima Bart on 2025-11-04.
//

import Foundation
import Testing
@testable import FlipcashCore

struct ExchangedFiatTests {
    
    static let rate = Rate(fx: 1.4, currency: .cad)
    
    static let lhs = try! ExchangedFiat(
        underlying: Quarks(
            quarks: 1_000_000 as UInt64,
            currencyCode: .usd,
            decimals: 10
        ),
        rate: rate,
        mint: .usdc
    )
    
    static let rhs = try! ExchangedFiat(
        underlying: Quarks(
            quarks: 500_000 as UInt64,
            currencyCode: .usd,
            decimals: 10
        ),
        rate: rate,
        mint: .usdc
    )
    
    // MARK: - Core -
    
    @Test
    static func testSimpleSubstraction() throws {
        let result = try lhs.subtracting(rhs)
        
        #expect(result.underlying.quarks == 500_000)
        #expect(result.rate        == rate)
        #expect(result.mint        == lhs.mint)
    }
    
    @Test
    static func testSubstractionErrors() throws {
        #expect(throws: ExchangedFiat.Error.mismatchedMint) {
            try lhs.subtracting(ExchangedFiat(underlying: 1, rate: rate, mint: .usdcAuthority))
        }
        
        #expect(throws: ExchangedFiat.Error.mismatchedMint) {
            try lhs.subtracting(ExchangedFiat(underlying: 1, rate: Rate(fx: 1.4, currency: .aed), mint: .usdcAuthority))
        }
    }
    
    // MARK: - Token Valuation -
    
    @Test
    static func testComputingValueFromSmallQuarks() throws {
        let usd = ExchangedFiat.computeFromQuarks(
            quarks: 55_14_59_074_093,
            mint: .usdcAuthority, // We don't want .usdc to simulate other tokens
            rate: Rate(fx: 1.0, currency: .usd),
            tvl: 1_000_000_000
        )

        let cad = ExchangedFiat.computeFromQuarks(
            quarks: 55_14_59_074_093,
            mint: .usdcAuthority,
            rate: Rate(fx: 1.4, currency: .cad),
            tvl: 1_000_000_000
        )

        // Note: Values updated for discrete bonding curve (was continuous)
        #expect(usd.underlying.quarks               == 55_14_59_074_093) // 55.12 Tokens
        #expect(usd.converted.quarks          ==    59_81_633_947) // ~0.59  USD
        #expect(usd.rate.fx.formatted(to: 10) == "0.0108469227")

        #expect(cad.underlying.quarks               == 55_14_59_074_093) // 55.12 Tokens
        #expect(cad.converted.quarks          ==    83_74_287_526) // ~0.83  CAD
        #expect(cad.rate.fx.formatted(to: 10) == "0.0151856918")
    }
    
    @Test
    static func testComputingValueFromZeroQuarks() throws {
        let usd = ExchangedFiat.computeFromQuarks(
            quarks: 0,
            mint: .usdcAuthority, // We don't want .usdc to simulate other tokens
            rate: Rate(fx: 1.0, currency: .usd),
            tvl: 1_000_000_000
        )

        #expect(usd.underlying.quarks == 0) // 0 Tokens
        #expect(usd.converted.quarks == 0) // $0 USD
        // Note: With 0 tokens, the exchange rate is 0 (no tokens to value)
        #expect(usd.rate.fx.formatted(to: 10) == "0.0000000000")
    }
    
    @Test
    static func testComputingValueFromLargeQuarks() throws {
        let usd = ExchangedFiat.computeFromQuarks(
            quarks: 100_500_14_59_074_093,
            mint: .usdcAuthority,
            rate: Rate(fx: 1.0, currency: .usd),
            tvl: 1_000_000_000_000
        )

        let cad = ExchangedFiat.computeFromQuarks(
            quarks: 100_500_14_59_074_093,
            mint: .usdcAuthority,
            rate: Rate(fx: 1.4, currency: .cad),
            tvl: 1_000_000_000_000
        )

        // Note: Values updated for discrete bonding curve (was continuous)
        #expect(usd.underlying.quarks               == 100_500_14_59_074_093) // 100,500.14 Tokens
        #expect(usd.converted.quarks          ==  853_384_553_496_705) // ~$85,338 USD
        #expect(usd.rate.fx.formatted(to: 10) == "0.8491376264")

        #expect(cad.underlying.quarks               == 100_500_14_59_074_093) // 100,500.14 Tokens
        #expect(cad.converted.quarks          == 1_194_738_374_895_387) // ~$119,473 CAD
        #expect(cad.rate.fx.formatted(to: 10) == "1.1887926770")
    }
    
    @Test
    static func testComputingQuarksFromFiat() throws {
        // Use a high TVL where bonded token conversion is meaningful
        let tvl: UInt64 = 100_000_000_000_000 // $100M in USDC quarks

        let usd = try #require(ExchangedFiat.computeFromEntered(
            amount: 0.59,
            rate: Rate(fx: 1.0, currency: .usd),
            mint: .usdcAuthority,
            tvl: tvl
        ))

        let cad = try #require(ExchangedFiat.computeFromEntered(
            amount: 0.59,
            rate: Rate(fx: 1.4, currency: .cad),
            mint: .usdcAuthority,
            tvl: tvl
        ))

        // CAD amount should require fewer tokens (since 1 CAD = 0.714 USD)
        let ratio = Decimal(usd.underlying.quarks) / Decimal(cad.underlying.quarks)
        #expect(ratio > 1.39 && ratio < 1.41, "USD/CAD ratio should be ~1.4")

        // Both should have non-zero underlying quarks
        #expect(usd.underlying.quarks > 0)
        #expect(cad.underlying.quarks > 0)

        // USD should require more tokens than CAD (same amount in different currencies)
        #expect(usd.underlying.quarks > cad.underlying.quarks)
    }
    
    // MARK: - Validating Fiat Values -
    
    @Test
    func testAmountsToSend() throws {
        // Test that computeFromEntered works for various TVL and fiat amounts
        let startTVL =     1_000_000_000_000 as UInt64 // $1M in USDC quarks
        let endTVL   = 100_000_000_000_000 as UInt64   // $100M

        let fiatToTest: [Decimal] = [
            5.00,
            10.00,
            100.00,
            500.00,
            1_000.00,
        ]

        var results: [(tvl: UInt64, fiat: Decimal, underlying: UInt64)] = []

        var tvl = startTVL
        while tvl <= endTVL {
            for fiat in fiatToTest {
                guard let exchanged = ExchangedFiat.computeFromEntered(
                    amount: fiat,
                    rate: .oneToOne,
                    mint: .usdcAuthority, // Not USDC
                    tvl: tvl
                ) else {
                    continue // Skip if amount exceeds what's available
                }

                results.append((tvl: tvl, fiat: fiat, underlying: exchanged.underlying.quarks))

                // Verify we got non-zero tokens
                #expect(exchanged.underlying.quarks > 0,
                       "At TVL \(tvl), should get tokens for \(fiat)")
            }

            tvl *= 10
        }

        // Should have processed all combinations
        #expect(results.count >= 15, "Should have at least 15 successful conversions")

        // Verify underlying quarks decrease as TVL increases (tokens become more expensive)
        // Compare same fiat amount at different TVL levels
        for fiat in fiatToTest {
            let filtered = results.filter { $0.fiat == fiat }.sorted { $0.tvl < $1.tvl }
            for i in 1..<filtered.count {
                #expect(filtered[i].underlying < filtered[i-1].underlying,
                       "At higher TVL, \(fiat) should require fewer tokens")
            }
        }
    }
    
    @Test
    func testQuarksToBalanceConversion() throws {
        let startTVL =           1_000_000 as UInt64 // USDC quarks (6dp)
        let endTVL   = 100_000_000_000_000 as UInt64 // 100,000

        let quarks = 1000_000_000_000 as UInt64 // 100 tokens

        var results: [(tvl: UInt64, converted: UInt64)] = []

        var tvl = startTVL
        while tvl <= endTVL {
            let exchanged = ExchangedFiat.computeFromQuarks(
                quarks: quarks,
                mint: .usdcAuthority,
                rate: .oneToOne,
                tvl: tvl
            )

            // Underlying quarks should always equal input
            #expect(exchanged.underlying.quarks == quarks)

            results.append((tvl: tvl, converted: exchanged.converted.quarks))
            tvl *= 10
        }

        // Converted value should increase as TVL increases
        // (tokens become more valuable at higher TVL due to bonding curve)
        for i in 1..<results.count {
            #expect(results[i].converted > results[i-1].converted,
                   "Converted value should increase with TVL: \(results[i-1].tvl) -> \(results[i].tvl)")
        }

        // Verify specific values for discrete bonding curve
        // Note: Values differ significantly from continuous curve at low TVL
        // because discrete curve uses step-based pricing
        let expectedConverted: [UInt64] = [
            10_000_000_000,      // ~$10,000 at TVL $1
            10_007_019_865,      // ~$10,007 at TVL $10
            10_086_333_721,      // ~$10,086 at TVL $100
            10_875_698_085,      // ~$10,876 at TVL $1,000
            18_769_280_254,      // ~$18,769 at TVL $10,000
            97_710_864_816,      // ~$97,711 at TVL $100,000
            887_078_196_317,     // ~$887,078 at TVL $1M
            8_780_977_354_499,   // ~$8.78M at TVL $10M
            87_717_392_699_354,  // ~$87.7M at TVL $100M
        ]

        for (i, expected) in expectedConverted.enumerated() {
            let actual = results[i].converted
            // Allow 1% tolerance for rounding differences
            let tolerance = max(expected / 100, 10_000) // At least $0.01 tolerance
            #expect(abs(Int64(actual) - Int64(expected)) <= Int64(tolerance),
                   "At TVL \(results[i].tvl): expected ~\(expected), got \(actual)")
        }
    }
}

private extension String {
    func padded(to characters: Int) -> String {
        let paddingCount = max(0, characters - self.count)
        return self + String(repeating: " ", count: paddingCount)
    }
}
