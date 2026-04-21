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
        let bondedMint = try PublicKey(base58: "54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25")
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
}

// MARK: - compute(fromEntered:) Integration Tests

@Suite("ExchangedFiat.compute(fromEntered:) - Bonding Curve Edge Cases")
struct ExchangedFiatComputeFromEnteredTests {

    /// These tests validate that compute(fromEntered:) handles edge cases
    /// gracefully without crashing.

    // Non-USDC mint to trigger bonding curve code path
    private let testMint = try! PublicKey(base58: "54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25")

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

    private let testMint: PublicKey = try! PublicKey(base58: "54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25")
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

    private static let testMint = try! PublicKey(base58: "54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25")
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
    private static let bondedTestMint = try! PublicKey(base58: "54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25")

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
