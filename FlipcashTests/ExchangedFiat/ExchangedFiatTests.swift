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

    // MARK: - Token Valuation -

    @Test
    static func testComputingValueFromSmallQuarks() throws {
        // 1000 tokens supply = 1000 * 10^10 quarks
        let supplyQuarks: UInt64 = 1000 * 10_000_000_000
        let quarksToConvert: UInt64 = 55_14_59_074_093

        let usd = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: quarksToConvert, mint: .jeffy),
            rate: Rate(fx: 1.0, currency: .usd),
            supplyQuarks: supplyQuarks
        )

        let cad = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: quarksToConvert, mint: .jeffy),
            rate: Rate(fx: 1.4, currency: .cad),
            supplyQuarks: supplyQuarks
        )

        // Verify on-chain quarks are preserved
        #expect(usd.onChainAmount.quarks == quarksToConvert)
        #expect(cad.onChainAmount.quarks == quarksToConvert)

        // Verify conversion produces positive values
        #expect(usd.nativeAmount.value > 0)
        #expect(cad.nativeAmount.value > 0)

        // Verify CAD value is higher than USD (due to fx rate of 1.4)
        #expect(cad.nativeAmount.value > usd.nativeAmount.value)

        // CAD native should be ~1.4x USD native
        let ratio = cad.nativeAmount.value / usd.nativeAmount.value
        #expect(ratio > 1.3 && ratio < 1.5, "CAD/USD ratio should be ~1.4")
    }

    @Test
    static func testComputingValueFromZeroQuarks() throws {
        // 1000 tokens supply = 1000 * 10^10 quarks
        let supplyQuarks: UInt64 = 1000 * 10_000_000_000

        let usd = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: 0, mint: .jeffy),
            rate: Rate(fx: 1.0, currency: .usd),
            supplyQuarks: supplyQuarks
        )

        #expect(usd.onChainAmount.quarks == 0) // 0 Tokens
        #expect(usd.usdfValue.value == 0)      // $0 USD
        #expect(usd.currencyRate.fx > 0)
    }

    @Test
    static func testComputingValueFromLargeQuarks() throws {
        // 100,000 tokens supply = 100,000 * 10^10 quarks
        let supplyQuarks: UInt64 = 100_000 * 10_000_000_000
        let quarksToConvert: UInt64 = 100_500_14_59_074_093

        let usd = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: quarksToConvert, mint: .jeffy),
            rate: Rate(fx: 1.0, currency: .usd),
            supplyQuarks: supplyQuarks
        )

        let cad = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: quarksToConvert, mint: .jeffy),
            rate: Rate(fx: 1.4, currency: .cad),
            supplyQuarks: supplyQuarks
        )

        // Verify on-chain quarks are preserved
        #expect(usd.onChainAmount.quarks == quarksToConvert)
        #expect(cad.onChainAmount.quarks == quarksToConvert)

        // Verify conversion produces positive values
        #expect(usd.nativeAmount.value > 0)
        #expect(cad.nativeAmount.value > 0)

        // Verify CAD value is higher than USD (due to fx rate of 1.4)
        #expect(cad.nativeAmount.value > usd.nativeAmount.value)

        // CAD native should be ~1.4x USD native
        let ratio = cad.nativeAmount.value / usd.nativeAmount.value
        #expect(ratio > 1.3 && ratio < 1.5, "CAD/USD ratio should be ~1.4")
    }

    @Test
    static func testComputingQuarksFromFiat() throws {
        // Use a reasonable supply where bonded token conversion is meaningful
        // 10,000 tokens supply = 10,000 * 10^10 quarks
        let supplyQuarks: UInt64 = 10_000 * 10_000_000_000

        let usd = try #require(ExchangedFiat.compute(
            fromEntered: FiatAmount(value: 0.59, currency: .usd),
            rate: Rate(fx: 1.0, currency: .usd),
            mint: .jeffy,
            supplyQuarks: supplyQuarks
        ))

        let cad = try #require(ExchangedFiat.compute(
            fromEntered: FiatAmount(value: 0.59, currency: .cad),
            rate: Rate(fx: 1.4, currency: .cad),
            mint: .jeffy,
            supplyQuarks: supplyQuarks
        ))

        // CAD amount should require fewer tokens (since 1 CAD = 0.714 USD)
        let ratio = Decimal(usd.onChainAmount.quarks) / Decimal(cad.onChainAmount.quarks)
        #expect(ratio > 1.39 && ratio < 1.41, "USD/CAD ratio should be ~1.4")

        // Both should have non-zero token quarks
        #expect(usd.onChainAmount.quarks > 0)
        #expect(cad.onChainAmount.quarks > 0)

        // USD should require more tokens than CAD (same amount in different currencies)
        #expect(usd.onChainAmount.quarks > cad.onChainAmount.quarks)
    }

    // MARK: - Validating Fiat Values -

    @Test
    func testAmountsToSend() throws {
        // Test that compute(fromEntered:) works for various supply levels and fiat amounts.
        //
        // New invariant: for a fixed USD input across supply levels, `usdfValue`
        // stays ≈ constant (it's a USD value) while `onChainAmount` varies with
        // supply — at higher supply, tokens are more valuable so a fixed USD
        // buys fewer tokens.
        //
        // (Previously this test locked in the buggy behavior that `.underlying`
        // decreased with rising supply, because `.underlying` was conflated
        // between USD and token quarks.)
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

        let curve = DiscreteBondingCurve()
        var results: [(supplyTokens: UInt64, fiat: Decimal, onChain: UInt64, usdf: Decimal)] = []

        var supplyTokens = startSupplyTokens
        while supplyTokens <= endSupplyTokens {
            let supplyQuarks = supplyTokens * quarksPerToken
            let currentTVL = curve.tokensToValue(currentSupply: 0, tokens: Int(supplyTokens))?.asDecimal()

            for fiat in fiatToTest {
                let shouldSucceed = currentTVL.map { fiat <= $0 } ?? false
                let exchanged = ExchangedFiat.compute(
                    fromEntered: FiatAmount(value: fiat, currency: .usd),
                    rate: .oneToOne,
                    mint: .jeffy, // Not USDF
                    supplyQuarks: supplyQuarks
                )

                if shouldSucceed {
                    #expect(exchanged != nil, "Expected exchange to succeed for \(fiat) at supply \(supplyTokens)")
                }

                guard let exchanged else {
                    continue // Skip if amount exceeds what's available
                }

                results.append((
                    supplyTokens: supplyTokens,
                    fiat: fiat,
                    onChain: exchanged.onChainAmount.quarks,
                    usdf: exchanged.usdfValue.value
                ))

                // Verify we got non-zero tokens
                #expect(exchanged.onChainAmount.quarks > 0,
                       "At supply \(supplyTokens) tokens, should get tokens for \(fiat)")
            }

            supplyTokens *= 10
        }

        // Verify onChain quarks decrease as supply increases (tokens become more expensive per $1).
        // Verify usdfValue stays approximately constant (it's a pure USD value).
        for fiat in fiatToTest {
            let filtered = results.filter { $0.fiat == fiat }.sorted { $0.supplyTokens < $1.supplyTokens }
            for i in 1..<filtered.count {
                #expect(filtered[i].onChain <= filtered[i-1].onChain,
                       "At higher supply, \(fiat) should buy fewer or equal tokens")

                // usdfValue ≈ fiat (1:1 rate), within bonding-curve rounding.
                let tolerance: Decimal = fiat * 0.02 // 2%
                let delta = abs(filtered[i].usdf - filtered[i-1].usdf)
                #expect(delta <= tolerance,
                       "usdfValue at fiat=\(fiat) should stay ≈ constant across supply levels")
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

        var results: [(supplyTokens: UInt64, native: Decimal)] = []

        var supplyTokens = startSupplyTokens
        while supplyTokens <= endSupplyTokens {
            let supplyQuarks = supplyTokens * quarksPerToken
            let exchanged = ExchangedFiat.compute(
                onChainAmount: TokenAmount(quarks: quarks, mint: .jeffy),
                rate: .oneToOne,
                supplyQuarks: supplyQuarks
            )

            // Token quarks should always equal input
            #expect(exchanged.onChainAmount.quarks == quarks)

            results.append((supplyTokens: supplyTokens, native: exchanged.nativeAmount.value))
            supplyTokens *= 10
        }

        // Native value should increase as supply increases
        // (tokens become more valuable at higher supply due to bonding curve)
        for i in 1..<results.count {
            #expect(results[i].native > results[i-1].native,
                   "Native value should increase with supply: \(results[i-1].supplyTokens) -> \(results[i].supplyTokens) tokens")
        }

        // Verify non-zero native values
        for result in results {
            #expect(result.native > 0, "Should have non-zero native value at \(result.supplyTokens) tokens supply")
        }
    }
}

private extension String {
    func padded(to characters: Int) -> String {
        let paddingCount = max(0, characters - self.count)
        return self + String(repeating: " ", count: paddingCount)
    }
}
