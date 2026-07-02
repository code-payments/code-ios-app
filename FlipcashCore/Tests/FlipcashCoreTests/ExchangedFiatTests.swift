//
//  ExchangedFiatTests.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-01.
//

import Foundation
import Testing
import FlipcashCore

@Suite("ExchangedFiat Tests")
struct ExchangedFiatTests {

    @Test("Subtract fee from amount")
    func testSubtractingFeeFromAmount() throws {
        let exchangedFiat = ExchangedFiat(
            nativeAmount: FiatAmount.usd(5.00),
            rate: .oneToOne
        )

        let fee = TokenAmount(quarks: 500_000, mint: .usdf) // $0.50 USDF

        let result = exchangedFiat.subtractingFee(fee)

        #expect(exchangedFiat.onChainAmount.quarks == 5_000_000)
        #expect(fee.quarks == 500_000)
        #expect(result.onChainAmount.quarks == 4_500_000)
    }

    @Test("Subtract fee equal to amount results in zero")
    func testSubtractingFeeEqualToAmount() throws {
        let exchangedFiat = ExchangedFiat(
            nativeAmount: FiatAmount.usd(0.50),
            rate: .oneToOne
        )

        let fee = TokenAmount(quarks: 500_000, mint: .usdf)

        let result = exchangedFiat.subtractingFee(fee)
        #expect(result.onChainAmount.quarks == 0)
    }

    @Test("Subtract same-mint same-rate ExchangedFiat preserves nativeAmount delta")
    func subtracting_sameMintSameRate_preservesNativeDelta() throws {
        let bondedMint = PublicKey.jeffy
        let rate = Rate.oneToOne

        let requested = ExchangedFiat(
            onChainAmount: TokenAmount(quarks: 10 * 10_000_000_000, mint: bondedMint),
            nativeAmount: FiatAmount.usd(1),
            currencyRate: rate
        )
        let balance = ExchangedFiat(
            onChainAmount: TokenAmount(quarks: 8 * 10_000_000_000, mint: bondedMint),
            nativeAmount: FiatAmount.usd(Decimal(string: "0.80")!),
            currencyRate: rate
        )

        let shortfall = requested.subtracting(balance)

        #expect(shortfall.onChainAmount.quarks == 2 * 10_000_000_000)
        #expect(shortfall.nativeAmount.value == Decimal(string: "0.20")!)
        #expect(shortfall.nativeAmount.currency == .usd)
        #expect(shortfall.currencyRate == rate)
    }

    @Test("Subtract with non-USD rate preserves rate on result")
    func subtracting_nonUSDRate_preservesRate() throws {
        let cadRate = Rate(fx: 1.4, currency: .cad)
        let requested = ExchangedFiat(
            onChainAmount: TokenAmount(quarks: 7_000_000, mint: .usdf), // 7 USDF
            nativeAmount: FiatAmount(value: Decimal(string: "9.80")!, currency: .cad),
            currencyRate: cadRate
        )
        let balance = ExchangedFiat(
            onChainAmount: TokenAmount(quarks: 5_000_000, mint: .usdf), // 5 USDF
            nativeAmount: FiatAmount(value: 7, currency: .cad),
            currencyRate: cadRate
        )

        let delta = requested.subtracting(balance)

        #expect(delta.onChainAmount.quarks == 2_000_000)
        #expect(delta.nativeAmount.value == Decimal(string: "2.80")!)
        #expect(delta.currencyRate.currency == .cad)
    }

    @Test("Subtract fee with non-USD rate recomputes native value")
    func testSubtractingFeeWithNonUSDRate() throws {
        let cadRate = Rate(fx: Decimal(1.4), currency: .cad)
        // $5 USD on-chain, native = $7 CAD
        let exchangedFiat = ExchangedFiat(
            nativeAmount: FiatAmount(value: 7.00, currency: .cad),
            rate: cadRate
        )

        // $0.50 USDF fee (on-chain)
        let fee = TokenAmount(quarks: 500_000, mint: .usdf)

        let result = exchangedFiat.subtractingFee(fee)

        #expect(result.onChainAmount.quarks == 4_500_000) // $4.50 USDF
        #expect(result.currencyRate.currency == .cad)
        // Native should be $4.50 * 1.4 = $6.30 CAD
        #expect(result.nativeAmount.value == Decimal(string: "6.30"))
    }

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

// MARK: - compute(fromEntered:) Integration Tests

@Suite("ExchangedFiat.compute(fromEntered:) - Bonding Curve Edge Cases")
struct ExchangedFiatComputeFromEnteredTests {

    /// These tests validate that compute(fromEntered:) handles edge cases
    /// gracefully without crashing.

    // Non-USDC mint to trigger bonding curve code path
    private let testMint = PublicKey.jeffy

    // Token supply uses 10 decimals: 1 token = 10^10 quarks
    private static let quarksPerToken: UInt64 = 10_000_000_000

    // 1000 tokens supply = 10^13 quarks
    private let testSupplyQuarks: UInt64 = 1000 * Self.quarksPerToken

    @Test("Zero supply returns nil (no TVL to exchange from)")
    func zeroSupplyReturnsNil() {
        // Zero supply means zero TVL - nothing to exchange from
        let result = ExchangedFiat.compute(
            fromEntered: FiatAmount.usd(5.0),
            rate: .oneToOne,
            mint: testMint,
            supplyQuarks: 0
        )

        #expect(result == nil, "Zero supply means zero TVL, exchange should return nil")
    }

    @Test("Zero amount returns nil")
    func zeroAmountReturnsNil() {
        let result = ExchangedFiat.compute(
            fromEntered: FiatAmount.usd(0),
            rate: .oneToOne,
            mint: testMint,
            supplyQuarks: testSupplyQuarks
        )

        #expect(result == nil, "Zero amount should return nil")
    }

    @Test("Valid exchange succeeds for non-USDC mint")
    func validExchangeSucceeds() {
        // $5 exchange with 1000 tokens supply - should succeed
        let result = ExchangedFiat.compute(
            fromEntered: FiatAmount.usd(5.0),
            rate: .oneToOne,
            mint: testMint,
            supplyQuarks: testSupplyQuarks
        )

        #expect(result != nil, "Valid exchange should succeed")
        if let result = result {
            #expect(result.nativeAmount.value > 0, "Should have positive native value")
            #expect(result.onChainAmount.quarks > 0, "Should have positive on-chain quarks")
        }
    }

    @Test("Small exchange with small supply succeeds - GiveViewModel scenario")
    func smallExchangeWithSmallSupply() {
        // User enters $0.50 with 100 tokens supply
        let result = ExchangedFiat.compute(
            fromEntered: FiatAmount.usd(0.50),
            rate: .oneToOne,
            mint: testMint,
            supplyQuarks: 100 * Self.quarksPerToken
        )

        #expect(result != nil, "$0.50 exchange with 100 tokens supply should succeed")
        if let result = result {
            #expect(result.nativeAmount.value > 0, "Should have positive native value")
            #expect(result.onChainAmount.quarks > 0, "Should have positive on-chain quarks")
        }
    }

    @Test("Valid exchange with non-USD currency succeeds")
    func validExchangeWithNonUSDCurrencySucceeds() {
        // $7 CAD at 1.4 rate = $5 USD, with 1000 tokens supply
        let cadRate = Rate(fx: Decimal(1.4), currency: .cad)
        let result = ExchangedFiat.compute(
            fromEntered: FiatAmount(value: 7.0, currency: .cad),
            rate: cadRate,
            mint: testMint,
            supplyQuarks: testSupplyQuarks
        )

        #expect(result != nil, "Valid CAD exchange should succeed")
        if let result = result {
            #expect(result.nativeAmount.value > 0)
            #expect(result.currencyRate.currency == .cad)
        }
    }

    @Test("USDF mint bypasses bonding curve and succeeds")
    func usdfMintBypassesBondingCurve() {
        // USDF doesn't use bonding curve, so zero supply shouldn't matter
        let result = ExchangedFiat.compute(
            fromEntered: FiatAmount.usd(5.0),
            rate: .oneToOne,
            mint: .usdf,
            supplyQuarks: 0  // Zero supply - should still work for USDF
        )

        #expect(result != nil, "USDF should bypass bonding curve")
    }

    @Test("Very small amount at small supply succeeds")
    func verySmallAmountAtSmallSupply() {
        // Small exchange at step 0 (supply < 100 tokens)
        let result = ExchangedFiat.compute(
            fromEntered: FiatAmount.usd(0.01),
            rate: .oneToOne,
            mint: testMint,
            supplyQuarks: 50 * Self.quarksPerToken  // 50 tokens
        )

        // Should succeed with valid result
        if let result = result {
            #expect(result.nativeAmount.value >= 0)
        }
        // Test passes as long as we don't crash
    }

    @Test("Caps to token balance when computed exceeds available")
    func capsToTokenBalance() {
        let balanceQuarks: UInt64 = Self.quarksPerToken // 1 token

        let result = ExchangedFiat.compute(
            fromEntered: FiatAmount.usd(5.0),
            rate: .oneToOne,
            mint: testMint,
            supplyQuarks: testSupplyQuarks,
            balance: nil,
            tokenBalanceQuarks: balanceQuarks
        )

        #expect(result != nil)
        #expect(result?.onChainAmount.quarks == balanceQuarks)
    }
}

// MARK: - compute(fromEntered:) Cap Tests

@Suite("ExchangedFiat.compute(fromEntered:) - Caps")
struct ExchangedFiatComputeFromEnteredCapTests {

    private let testMint: PublicKey = .jeffy
    private let testSupplyQuarks: UInt64 = 100_000 * 10_000_000_000

    @Test("Caps entered amount to USDF balance")
    func capsToUsdfBalance() throws {
        let rate = Rate(fx: Decimal(1.4), currency: .cad)
        let balance = FiatAmount.usd(Decimal(10.41))

        let result = ExchangedFiat.compute(
            fromEntered: FiatAmount(value: 20.00, currency: .cad),
            rate: rate,
            mint: testMint,
            supplyQuarks: testSupplyQuarks,
            balance: balance
        )

        #expect(result != nil)
        // Expected capped native: 10.41 USD → 10.41 * 1.4 = 14.574 CAD
        let expectedNative = balance.value * rate.fx
        if let native = result?.nativeAmount.value {
            // Allow small bonding-curve rounding tolerance
            #expect(abs(native - expectedNative) < Decimal(0.01))
        }
    }

    @Test("Applies USDF cap before token cap")
    func appliesUsdfAndTokenCaps() throws {
        let rate = Rate(fx: Decimal(1.0), currency: .usd)
        let balance = FiatAmount.usd(10)
        let tokenBalanceQuarks: UInt64 = 10_000_000_000 // 1 token

        let result = ExchangedFiat.compute(
            fromEntered: FiatAmount.usd(100),
            rate: rate,
            mint: testMint,
            supplyQuarks: testSupplyQuarks,
            balance: balance,
            tokenBalanceQuarks: tokenBalanceQuarks
        )

        #expect(result != nil)
        #expect(result?.onChainAmount.quarks == tokenBalanceQuarks)
        if let native = result?.nativeAmount.value {
            #expect(native <= balance.value * rate.fx)
        }
    }

    @Test("Full-balance sell never exceeds token balance")
    func fullBalanceSellDoesNotExceedTokenBalance() throws {
        let rate = Rate(fx: Decimal(1.4), currency: .cad)
        let tokenBalanceQuarks: UInt64 = 2 * 10_000_000_000

        let result = ExchangedFiat.compute(
            fromEntered: FiatAmount(value: 14.10, currency: .cad),
            rate: rate,
            mint: testMint,
            supplyQuarks: testSupplyQuarks,
            tokenBalanceQuarks: tokenBalanceQuarks
        )

        let quarks = try #require(result?.onChainAmount.quarks)
        #expect(quarks <= tokenBalanceQuarks)
    }

    @Test("Zero-decimal currency respects USDF cap")
    func zeroDecimalCurrencyRespectsCap() throws {
        let rate = Rate(fx: Decimal(150), currency: .jpy)
        let balance = FiatAmount.usd(Decimal(1.23))

        let result = ExchangedFiat.compute(
            fromEntered: FiatAmount(value: 200, currency: .jpy),
            rate: rate,
            mint: testMint,
            supplyQuarks: testSupplyQuarks,
            balance: balance
        )

        #expect(result != nil)
        #expect(result?.nativeAmount.currency == .jpy)
        // Capped native: 1.23 USD * 150 = 184.5 JPY
        let expected = balance.value * rate.fx
        if let native = result?.nativeAmount.value {
            #expect(abs(native - expected) < Decimal(1))
        }
    }
}

// MARK: - Server Consistency Tests

@Suite("ExchangedFiat.compute(fromEntered:) - Server Consistency")
struct ExchangedFiatServerConsistencyTests {

    private static let testMint = PublicKey.jeffy
    private static let quarksPerToken: UInt64 = 10_000_000_000

    private static let bondedTokenCases: [(amount: Decimal, rate: Rate, supplyTokens: UInt64)] = [
        (Decimal(string: "326.79")!, Rate(fx: 1.4, currency: .cad), 1_000_000),
        (100,                        Rate(fx: 1.4, currency: .cad), 100_000),
        (10000,                      .oneToOne,                     10_000_000),
        (Decimal(string: "0.50")!,   .oneToOne,                     100),
    ]

    @Test(
        "Bonded token fiat matches server direction",
        arguments: bondedTokenCases
    )
    func bondedTokenServerConsistency(
        amount: Decimal, rate: Rate, supplyTokens: UInt64
    ) throws {
        let supplyQuarks = supplyTokens * Self.quarksPerToken

        let fromEntered = try #require(ExchangedFiat.compute(
            fromEntered: FiatAmount(value: amount, currency: rate.currency),
            rate: rate,
            mint: Self.testMint,
            supplyQuarks: supplyQuarks
        ))

        let fromQuarks = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: fromEntered.onChainAmount.quarks, mint: Self.testMint),
            rate: rate,
            supplyQuarks: supplyQuarks
        )

        #expect(fromEntered.nativeAmount.value == fromQuarks.nativeAmount.value)
    }

    @Test("USDF bypasses bonding curve, no divergence possible")
    func usdfNoDivergence() throws {
        let fromEntered = try #require(ExchangedFiat.compute(
            fromEntered: FiatAmount.usd(Decimal(string: "326.79")!),
            rate: .oneToOne,
            mint: .usdf,
            supplyQuarks: 0
        ))

        let fromQuarks = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: fromEntered.onChainAmount.quarks, mint: .usdf),
            rate: .oneToOne,
            supplyQuarks: nil
        )

        #expect(fromEntered.nativeAmount.value == fromQuarks.nativeAmount.value)
    }
}

// MARK: - Collection.total Tests

@Suite("ExchangedFiat Collection.total")
struct ExchangedFiatTotalTests {

    private static let usdRate = Rate.oneToOne
    private static let cadRate = Rate(fx: 1.4, currency: .cad)
    private static let bondedTestMint = PublicKey.jeffy

    @Test("Total of empty collection returns zero")
    func emptyCollection() {
        let items: [ExchangedFiat] = []
        let result = items.total(rate: Self.usdRate)

        #expect(result.onChainAmount.quarks == 0)
        #expect(result.nativeAmount.value == 0)
        #expect(result.mint == PublicKey.usdf)
    }

    @Test("Total of single element equals that element")
    func singleElement() throws {
        let item = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: 5_000_000, mint: .usdf),
            rate: Self.usdRate,
            supplyQuarks: nil
        )

        let result = [item].total(rate: Self.usdRate)

        #expect(result.onChainAmount.quarks == item.onChainAmount.quarks)
        #expect(result.nativeAmount.value == item.nativeAmount.value)
    }

    @Test("Total sums multiple USDF balances")
    func multipleUSDF() throws {
        let a = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: 3_000_000, mint: .usdf),
            rate: Self.usdRate,
            supplyQuarks: nil
        )
        let b = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: 5_000_000, mint: .usdf),
            rate: Self.usdRate,
            supplyQuarks: nil
        )

        let result = [a, b].total(rate: Self.usdRate)

        #expect(result.usdfValue.value == 8)
        #expect(result.nativeAmount.value == 8)
    }

    @Test("Total preserves rate currency")
    func preservesCurrency() throws {
        let item = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: 1_000_000, mint: .usdf),
            rate: Self.cadRate,
            supplyQuarks: nil
        )

        let result = [item].total(rate: Self.cadRate)

        #expect(result.currencyRate.currency == .cad)
        #expect(result.nativeAmount.currency == .cad)
    }

    @Test("Total sums mixed mints correctly")
    func mixedMints() throws {
        // USDF balance: $3.00
        let usdfBalance = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: 3_000_000, mint: .usdf),
            rate: Self.usdRate,
            supplyQuarks: nil
        )

        // Bonded token balance
        let supplyQuarks: UInt64 = 1000 * 10_000_000_000
        let bondedBalance = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: 50_000_000_000, mint: Self.bondedTestMint),
            rate: Self.usdRate,
            supplyQuarks: supplyQuarks
        )

        let result = [usdfBalance, bondedBalance].total(rate: Self.usdRate)

        // Total USDF/native should exceed the USDF-only balance
        #expect(result.usdfValue.value > usdfBalance.usdfValue.value)
        #expect(result.nativeAmount.value > usdfBalance.nativeAmount.value)
        #expect(result.mint == PublicKey.usdf)
    }
}
