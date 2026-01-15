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
        mint: .usdf
    )
    
    static let rhs = try! ExchangedFiat(
        underlying: Quarks(
            quarks: 500_000 as UInt64,
            currencyCode: .usd,
            decimals: 10
        ),
        rate: rate,
        mint: .usdf
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
        // 1000 tokens supply = 1000 * 10^10 quarks
        let supplyQuarks: UInt64 = 1000 * 10_000_000_000
        let quarksToConvert: UInt64 = 55_14_59_074_093

        let usd = ExchangedFiat.computeFromQuarks(
            quarks: quarksToConvert,
            mint: .jeffy, // Use a non-USDF mint to simulate bonded tokens
            rate: Rate(fx: 1.0, currency: .usd),
            supplyQuarks: supplyQuarks
        )

        let cad = ExchangedFiat.computeFromQuarks(
            quarks: quarksToConvert,
            mint: .jeffy,
            rate: Rate(fx: 1.4, currency: .cad),
            supplyQuarks: supplyQuarks
        )

        // Verify underlying quarks are preserved
        #expect(usd.underlying.quarks == quarksToConvert)
        #expect(cad.underlying.quarks == quarksToConvert)

        // Verify conversion produces positive values
        #expect(usd.converted.quarks > 0)
        #expect(cad.converted.quarks > 0)

        // Verify CAD value is higher than USD (due to fx rate of 1.4)
        #expect(cad.converted.quarks > usd.converted.quarks)

        // Verify the rate produces reasonable conversion
        // CAD converted should be ~1.4x USD converted
        let ratio = Double(cad.converted.quarks) / Double(usd.converted.quarks)
        #expect(ratio > 1.3 && ratio < 1.5, "CAD/USD ratio should be ~1.4")
    }
    
    @Test
    static func testComputingValueFromZeroQuarks() throws {
        // 1000 tokens supply = 1000 * 10^10 quarks
        let supplyQuarks: UInt64 = 1000 * 10_000_000_000

        let usd = ExchangedFiat.computeFromQuarks(
            quarks: 0,
            mint: .jeffy, // Use a non-USDF mint to simulate bonded tokens
            rate: Rate(fx: 1.0, currency: .usd),
            supplyQuarks: supplyQuarks
        )

        #expect(usd.underlying.quarks == 0) // 0 Tokens
        #expect(usd.converted.quarks == 0) // $0 USD
        // Note: With 0 tokens, the exchange rate is 0 (no tokens to value)
        #expect(usd.rate.fx.formatted(to: 10) == "0.0000000000")
    }
    
    @Test
    static func testComputingValueFromLargeQuarks() throws {
        // 100,000 tokens supply = 100,000 * 10^10 quarks
        let supplyQuarks: UInt64 = 100_000 * 10_000_000_000
        let quarksToConvert: UInt64 = 100_500_14_59_074_093

        let usd = ExchangedFiat.computeFromQuarks(
            quarks: quarksToConvert,
            mint: .jeffy,
            rate: Rate(fx: 1.0, currency: .usd),
            supplyQuarks: supplyQuarks
        )

        let cad = ExchangedFiat.computeFromQuarks(
            quarks: quarksToConvert,
            mint: .jeffy,
            rate: Rate(fx: 1.4, currency: .cad),
            supplyQuarks: supplyQuarks
        )

        // Verify underlying quarks are preserved
        #expect(usd.underlying.quarks == quarksToConvert)
        #expect(cad.underlying.quarks == quarksToConvert)

        // Verify conversion produces positive values
        #expect(usd.converted.quarks > 0)
        #expect(cad.converted.quarks > 0)

        // Verify CAD value is higher than USD (due to fx rate of 1.4)
        #expect(cad.converted.quarks > usd.converted.quarks)

        // Verify the rate produces reasonable conversion
        // CAD converted should be ~1.4x USD converted
        let ratio = Double(cad.converted.quarks) / Double(usd.converted.quarks)
        #expect(ratio > 1.3 && ratio < 1.5, "CAD/USD ratio should be ~1.4")
    }
    
    @Test
    static func testComputingQuarksFromFiat() throws {
        // Use a reasonable supply where bonded token conversion is meaningful
        // 10,000 tokens supply = 10,000 * 10^10 quarks
        let supplyQuarks: UInt64 = 10_000 * 10_000_000_000

        let usd = try #require(ExchangedFiat.computeFromEntered(
            amount: 0.59,
            rate: Rate(fx: 1.0, currency: .usd),
            mint: .jeffy,
            supplyQuarks: supplyQuarks
        ))

        let cad = try #require(ExchangedFiat.computeFromEntered(
            amount: 0.59,
            rate: Rate(fx: 1.4, currency: .cad),
            mint: .jeffy,
            supplyQuarks: supplyQuarks
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
        // Test that computeFromEntered works for various supply levels and fiat amounts
        // Supply in tokens: 1000, 10000, 100000 tokens
        let startSupplyTokens: UInt64 = 1_000
        let endSupplyTokens: UInt64 = 100_000
        let quarksPerToken: UInt64 = 10_000_000_000

        let fiatToTest: [Decimal] = [
            5.00,
            10.00,
            100.00,
            500.00,
            1_000.00,
        ]

        var results: [(supplyTokens: UInt64, fiat: Decimal, underlying: UInt64)] = []

        var supplyTokens = startSupplyTokens
        while supplyTokens <= endSupplyTokens {
            let supplyQuarks = supplyTokens * quarksPerToken
            for fiat in fiatToTest {
                guard let exchanged = ExchangedFiat.computeFromEntered(
                    amount: fiat,
                    rate: .oneToOne,
                    mint: .jeffy, // Not USDF
                    supplyQuarks: supplyQuarks
                ) else {
                    continue // Skip if amount exceeds what's available
                }

                results.append((supplyTokens: supplyTokens, fiat: fiat, underlying: exchanged.underlying.quarks))

                // Verify we got non-zero tokens
                #expect(exchanged.underlying.quarks > 0,
                       "At supply \(supplyTokens) tokens, should get tokens for \(fiat)")
            }

            supplyTokens *= 10
        }

        // Should have processed all combinations
        #expect(results.count >= 15, "Should have at least 15 successful conversions")

        // Verify underlying quarks decrease as supply increases (tokens become more expensive)
        // Compare same fiat amount at different supply levels
        for fiat in fiatToTest {
            let filtered = results.filter { $0.fiat == fiat }.sorted { $0.supplyTokens < $1.supplyTokens }
            for i in 1..<filtered.count {
                #expect(filtered[i].underlying < filtered[i-1].underlying,
                       "At higher supply, \(fiat) should buy fewer tokens")
            }
        }
    }
    
    @Test
    func testQuarksToBalanceConversion() throws {
        // Test supply from 100 tokens to 1,000,000 tokens
        let startSupplyTokens: UInt64 = 100
        let endSupplyTokens: UInt64 = 1_000_000
        let quarksPerToken: UInt64 = 10_000_000_000

        let quarks = 100 * quarksPerToken as UInt64 // 100 tokens

        var results: [(supplyTokens: UInt64, converted: UInt64)] = []

        var supplyTokens = startSupplyTokens
        while supplyTokens <= endSupplyTokens {
            let supplyQuarks = supplyTokens * quarksPerToken
            let exchanged = ExchangedFiat.computeFromQuarks(
                quarks: quarks,
                mint: .jeffy,
                rate: .oneToOne,
                supplyQuarks: supplyQuarks
            )

            // Underlying quarks should always equal input
            #expect(exchanged.underlying.quarks == quarks)

            results.append((supplyTokens: supplyTokens, converted: exchanged.converted.quarks))
            supplyTokens *= 10
        }

        // Converted value should increase as supply increases
        // (tokens become more valuable at higher supply due to bonding curve)
        for i in 1..<results.count {
            #expect(results[i].converted > results[i-1].converted,
                   "Converted value should increase with supply: \(results[i-1].supplyTokens) -> \(results[i].supplyTokens) tokens")
        }

        // Verify non-zero converted values
        for result in results {
            #expect(result.converted > 0, "Should have non-zero converted value at \(result.supplyTokens) tokens supply")
        }
    }
}

private extension String {
    func padded(to characters: Int) -> String {
        let paddingCount = max(0, characters - self.count)
        return self + String(repeating: " ", count: paddingCount)
    }
}
