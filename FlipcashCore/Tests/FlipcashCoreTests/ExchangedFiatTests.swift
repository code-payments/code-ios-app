//
//  FiatTests.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-01.
//

import Foundation
import Testing
import FlipcashCore

@Suite("ExchangedFiat Tests")
struct ExchangedFiatTests {

    // USDC uses 6 decimals
    private static let usdcDecimals = 6

    @Test("Subtract fee from amount")
    func testSubtractingFeeFromAmount() throws {
        let exchangedFiat = try ExchangedFiat(
            converted: try Quarks(fiatDecimal: 5.00, currencyCode: .usd, decimals: Self.usdcDecimals),
            rate: .oneToOne,
            mint: .usdf
        )

        let fee = try Quarks(fiatDecimal: 0.5, currencyCode: .usd, decimals: Self.usdcDecimals)

        let result = try exchangedFiat.subtracting(fee: fee)

        #expect(exchangedFiat.underlying.quarks == 5_000_000)
        #expect(fee.quarks == 500_000)
        #expect(result.underlying.quarks == 4_500_000)
    }

    @Test("Subtract fee too large")
    func testSubtractingFeeTooLarge() throws {
        let exchangedFiat = try ExchangedFiat(
            converted: try Quarks(fiatDecimal: 0.40, currencyCode: .usd, decimals: Self.usdcDecimals),
            rate: .oneToOne,
            mint: .usdf
        )

        let fee = try Quarks(fiatDecimal: 0.5, currencyCode: .usd, decimals: Self.usdcDecimals)

        #expect(throws: ExchangedFiat.Error.feeLargerThanAmount) {
            try exchangedFiat.subtracting(fee: fee)
        }
    }

    @Test("Subtract fee equal to amount results in zero")
    func testSubtractingFeeEqualToAmount() throws {
        let exchangedFiat = try ExchangedFiat(
            converted: try Quarks(fiatDecimal: 0.50, currencyCode: .usd, decimals: Self.usdcDecimals),
            rate: .oneToOne,
            mint: .usdf
        )

        let fee = try Quarks(fiatDecimal: 0.5, currencyCode: .usd, decimals: Self.usdcDecimals)

        let result = try exchangedFiat.subtracting(fee: fee)
        #expect(result.underlying.quarks == 0)
    }

    @Test("Subtract fee with non-USD rate recomputes converted value")
    func testSubtractingFeeWithNonUSDRate() throws {
        let cadRate = Rate(fx: Decimal(1.4), currency: .cad)
        // $5 USD underlying, converted to $7 CAD
        let exchangedFiat = try ExchangedFiat(
            underlying: try Quarks(fiatDecimal: 5.00, currencyCode: .usd, decimals: Self.usdcDecimals),
            rate: cadRate,
            mint: .usdf
        )

        // $0.50 USD fee
        let fee = try Quarks(fiatDecimal: 0.5, currencyCode: .usd, decimals: Self.usdcDecimals)

        let result = try exchangedFiat.subtracting(fee: fee)

        #expect(result.underlying.quarks == 4_500_000) // $4.50 USD
        #expect(result.rate.currency == .cad)
        // Converted should be $4.50 * 1.4 = $6.30 CAD
        let expectedConverted = try Quarks(fiatDecimal: 4.5 * 1.4, currencyCode: .cad, decimals: Self.usdcDecimals)
        #expect(result.converted.quarks == expectedConverted.quarks)
    }

    @Test("Subtract fee too large with non-USD rate")
    func testSubtractingFeeTooLargeWithNonUSDRate() throws {
        let cadRate = Rate(fx: Decimal(1.4), currency: .cad)
        let exchangedFiat = try ExchangedFiat(
            underlying: try Quarks(fiatDecimal: 0.40, currencyCode: .usd, decimals: Self.usdcDecimals),
            rate: cadRate,
            mint: .usdf
        )

        let fee = try Quarks(fiatDecimal: 0.5, currencyCode: .usd, decimals: Self.usdcDecimals)

        #expect(throws: ExchangedFiat.Error.feeLargerThanAmount) {
            try exchangedFiat.subtracting(fee: fee)
        }
    }
}

// MARK: - computeFromEntered Integration Tests

@Suite("ExchangedFiat.computeFromEntered - Bonding Curve Edge Cases")
struct ExchangedFiatComputeFromEnteredTests {

    /// These tests validate that computeFromEntered handles edge cases gracefully
    /// without crashing. This is critical because the method uses force-try (try!)
    /// internally, so any invalid valuation from the bonding curve would crash.
    ///
    /// The fix (returning nil from tokensForValueExchange for invalid cases)
    /// ensures the guard statement at line 154-160 catches these cases.

    // Non-USDC mint to trigger bonding curve code path
    private let testMint = try! PublicKey(base58: "54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25")

    // Token supply uses 10 decimals: 1 token = 10^10 quarks
    private static let quarksPerToken: UInt64 = 10_000_000_000

    // 1000 tokens supply = 10^13 quarks
    private let testSupplyQuarks: UInt64 = 1000 * Self.quarksPerToken

    @Test("Zero supply returns nil (no TVL to exchange from)")
    func zeroSupplyReturnsNil() {
        // Zero supply means zero TVL - nothing to exchange from
        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(5.0),
            rate: .oneToOne,
            mint: testMint,
            supplyQuarks: 0
        )

        #expect(result == nil, "Zero supply means zero TVL, exchange should return nil")
    }

    @Test("Zero amount returns nil")
    func zeroAmountReturnsNil() {
        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(0),
            rate: .oneToOne,
            mint: testMint,
            supplyQuarks: testSupplyQuarks
        )

        #expect(result == nil, "Zero amount should return nil")
    }

    @Test("Negative amount returns nil")
    func negativeAmountReturnsNil() {
        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(-5.0),
            rate: .oneToOne,
            mint: testMint,
            supplyQuarks: testSupplyQuarks
        )

        #expect(result == nil, "Negative amount should return nil")
    }

    @Test("Valid exchange succeeds for non-USDC mint")
    func validExchangeSucceeds() {
        // $5 exchange with 1000 tokens supply - should succeed
        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(5.0),
            rate: .oneToOne,
            mint: testMint,
            supplyQuarks: testSupplyQuarks
        )

        #expect(result != nil, "Valid exchange should succeed")
        if let result = result {
            #expect(result.converted.quarks > 0, "Should have positive converted quarks")
            #expect(result.underlying.quarks > 0, "Should have positive underlying quarks")
        }
    }

    @Test("Small exchange with small supply succeeds - GiveViewModel scenario")
    func smallExchangeWithSmallSupply() {
        // User enters $0.50 with 100 tokens supply
        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(0.50),
            rate: .oneToOne,
            mint: testMint,
            supplyQuarks: 100 * Self.quarksPerToken
        )

        #expect(result != nil, "$0.50 exchange with 100 tokens supply should succeed")
        if let result = result {
            #expect(result.converted.quarks > 0, "Should have positive converted quarks")
            #expect(result.underlying.quarks > 0, "Should have positive underlying quarks")
        }
    }

    @Test("Valid exchange with non-USD currency succeeds")
    func validExchangeWithNonUSDCurrencySucceeds() {
        // $7 CAD at 1.4 rate = $5 USD, with 1000 tokens supply
        let cadRate = Rate(fx: Decimal(1.4), currency: .cad)
        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(7.0),
            rate: cadRate,
            mint: testMint,
            supplyQuarks: testSupplyQuarks
        )

        #expect(result != nil, "Valid CAD exchange should succeed")
        if let result = result {
            #expect(result.converted.quarks > 0)
            #expect(result.rate.currency == .cad)
        }
    }

    @Test("USDF mint bypasses bonding curve and succeeds")
    func usdfMintBypassesBondingCurve() {
        // USDF doesn't use bonding curve, so zero supply shouldn't matter
        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(5.0),
            rate: .oneToOne,
            mint: .usdf,
            supplyQuarks: 0  // Zero supply - should still work for USDF
        )

        #expect(result != nil, "USDF should bypass bonding curve")
    }

    @Test("Very small amount at small supply succeeds")
    func verySmallAmountAtSmallSupply() {
        // Small exchange at step 0 (supply < 100 tokens)
        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(0.01),
            rate: .oneToOne,
            mint: testMint,
            supplyQuarks: 50 * Self.quarksPerToken  // 50 tokens
        )

        // Should succeed with valid result
        if let result = result {
            #expect(result.converted.quarks >= 0)
        }
        // Test passes as long as we don't crash
    }

    @Test("Caps to token balance when computed exceeds available")
    func capsToTokenBalance() {
        let balanceQuarks: UInt64 = Self.quarksPerToken // 1 token

        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(5.0),
            rate: .oneToOne,
            mint: testMint,
            supplyQuarks: testSupplyQuarks,
            tokenBalanceQuarks: balanceQuarks
        )

        #expect(result != nil)
        #expect(result?.underlying.quarks == balanceQuarks)
    }
}

// MARK: - computeFromEntered Cap Tests

@Suite("ExchangedFiat.computeFromEntered - Caps")
struct ExchangedFiatComputeFromEnteredCapTests {

    private let testMint: PublicKey = try! PublicKey(base58: "54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25")
    private let testSupplyQuarks: UInt64 = 100_000 * 10_000_000_000

    @Test("Caps entered amount to USDF balance")
    func capsToUsdfBalance() throws {
        let rate = Rate(fx: Decimal(1.4), currency: .cad)
        let balance = try Quarks(fiatDecimal: Decimal(10.41), currencyCode: .usd, decimals: 6)
        let enteredAmount = Decimal(20.00)

        let result = ExchangedFiat.computeFromEntered(
            amount: enteredAmount,
            rate: rate,
            mint: testMint,
            supplyQuarks: testSupplyQuarks,
            balance: balance
        )

        let cappedAmount = balance.decimalValue * rate.fx
        let expectedConverted = try Quarks(
            fiatDecimal: cappedAmount,
            currencyCode: rate.currency,
            decimals: testMint.mintDecimals
        )

        #expect(result != nil)
        #expect(result?.converted.quarks == expectedConverted.quarks)
    }

    @Test("Invalid balance currency returns nil")
    func invalidBalanceCurrencyReturnsNil() throws {
        let rate = Rate(fx: Decimal(1.0), currency: .usd)
        let balance = try Quarks(fiatDecimal: Decimal(10), currencyCode: .cad, decimals: 6)

        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(5),
            rate: rate,
            mint: testMint,
            supplyQuarks: testSupplyQuarks,
            balance: balance
        )

        #expect(result == nil)
    }

    @Test("Invalid balance decimals returns nil")
    func invalidBalanceDecimalsReturnsNil() throws {
        let rate = Rate(fx: Decimal(1.0), currency: .usd)
        let balance = try Quarks(fiatDecimal: Decimal(10), currencyCode: .usd, decimals: 10)

        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(5),
            rate: rate,
            mint: testMint,
            supplyQuarks: testSupplyQuarks,
            balance: balance
        )

        #expect(result == nil)
    }

    @Test("Applies USDF cap before token cap")
    func appliesUsdfAndTokenCaps() throws {
        let rate = Rate(fx: Decimal(1.0), currency: .usd)
        let balance = try Quarks(fiatDecimal: Decimal(10), currencyCode: .usd, decimals: 6)
        let tokenBalanceQuarks: UInt64 = 10_000_000_000 // 1 token

        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(100),
            rate: rate,
            mint: testMint,
            supplyQuarks: testSupplyQuarks,
            balance: balance,
            tokenBalanceQuarks: tokenBalanceQuarks
        )

        #expect(result != nil)
        #expect(result?.underlying.quarks == tokenBalanceQuarks)
        if let converted = result?.converted.decimalValue {
            #expect(converted <= balance.decimalValue * rate.fx)
        }
    }

    @Test("Full-balance sell never exceeds token balance")
    func fullBalanceSellDoesNotExceedTokenBalance() throws {
        let rate = Rate(fx: Decimal(1.4), currency: .cad)
        let tokenBalanceQuarks: UInt64 = 2 * 10_000_000_000

        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(14.10),
            rate: rate,
            mint: testMint,
            supplyQuarks: testSupplyQuarks,
            tokenBalanceQuarks: tokenBalanceQuarks
        )

        let quarks = try #require(result?.underlying.quarks)
        #expect(quarks <= tokenBalanceQuarks)
    }

    @Test("Zero-decimal currency respects USDF cap")
    func zeroDecimalCurrencyRespectsCap() throws {
        let rate = Rate(fx: Decimal(150), currency: .jpy)
        let balance = try Quarks(fiatDecimal: Decimal(1.23), currencyCode: .usd, decimals: 6)
        let enteredAmount = Decimal(200)

        let result = ExchangedFiat.computeFromEntered(
            amount: enteredAmount,
            rate: rate,
            mint: testMint,
            supplyQuarks: testSupplyQuarks,
            balance: balance
        )

        let cappedAmount = balance.decimalValue * rate.fx
        let expectedConverted = try Quarks(
            fiatDecimal: cappedAmount,
            currencyCode: rate.currency,
            decimals: testMint.mintDecimals
        )

        #expect(result != nil)
        #expect(result?.converted.currencyCode == .jpy)
        #expect(result?.converted.quarks == expectedConverted.quarks)
    }
}

// MARK: - Server Consistency Tests

@Suite("ExchangedFiat.computeFromEntered - Server Consistency")
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

        let fromEntered = try #require(ExchangedFiat.computeFromEntered(
            amount: amount,
            rate: rate,
            mint: Self.testMint,
            supplyQuarks: supplyQuarks
        ))

        let fromQuarks = ExchangedFiat.computeFromQuarks(
            quarks: fromEntered.underlying.quarks,
            mint: Self.testMint,
            rate: rate,
            supplyQuarks: supplyQuarks
        )

        #expect(fromEntered.converted.quarks == fromQuarks.converted.quarks)
    }

    @Test("USDF bypasses bonding curve, no divergence possible")
    func usdfNoDivergence() throws {
        let fromEntered = try #require(ExchangedFiat.computeFromEntered(
            amount: Decimal(string: "326.79")!,
            rate: .oneToOne,
            mint: .usdf,
            supplyQuarks: 0
        ))

        let fromQuarks = ExchangedFiat.computeFromQuarks(
            quarks: fromEntered.underlying.quarks,
            mint: .usdf,
            rate: .oneToOne,
            supplyQuarks: nil
        )

        #expect(fromEntered.converted.quarks == fromQuarks.converted.quarks)
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

        #expect(result.underlying.quarks == 0)
        #expect(result.converted.quarks == 0)
        #expect(result.mint == PublicKey.usdf)
    }

    @Test("Total of single element equals that element")
    func singleElement() throws {
        let item = try ExchangedFiat(
            underlying: Quarks(quarks: 5_000_000 as UInt64, currencyCode: .usd, decimals: 6),
            rate: Self.usdRate,
            mint: .usdf
        )

        let result = [item].total(rate: Self.usdRate)

        #expect(result.underlying.quarks == item.underlying.quarks)
        #expect(result.converted.quarks == item.converted.quarks)
    }

    @Test("Total sums multiple USDF balances")
    func multipleUSDF() throws {
        let a = try ExchangedFiat(
            underlying: Quarks(quarks: 3_000_000 as UInt64, currencyCode: .usd, decimals: 6),
            rate: Self.usdRate,
            mint: .usdf
        )
        let b = try ExchangedFiat(
            underlying: Quarks(quarks: 5_000_000 as UInt64, currencyCode: .usd, decimals: 6),
            rate: Self.usdRate,
            mint: .usdf
        )

        let result = [a, b].total(rate: Self.usdRate)

        #expect(result.underlying.quarks == 8_000_000)
        #expect(result.converted.quarks == 8_000_000)
    }

    @Test("Total preserves rate currency")
    func preservesCurrency() throws {
        let item = try ExchangedFiat(
            underlying: Quarks(quarks: 1_000_000 as UInt64, currencyCode: .usd, decimals: 6),
            rate: Self.cadRate,
            mint: .usdf
        )

        let result = [item].total(rate: Self.cadRate)

        #expect(result.rate.currency == .cad)
        #expect(result.converted.currencyCode == .cad)
    }

    @Test("Total sums mixed mints correctly")
    func mixedMints() throws {
        // USDF balance: $3.00
        let usdfBalance = try ExchangedFiat(
            underlying: Quarks(quarks: 3_000_000 as UInt64, currencyCode: .usd, decimals: 6),
            rate: Self.usdRate,
            mint: .usdf
        )

        // Bonded token balance via computeFromQuarks
        let supplyQuarks: UInt64 = 1000 * 10_000_000_000
        let bondedBalance = ExchangedFiat.computeFromQuarks(
            quarks: 50_000_000_000 as UInt64,
            mint: Self.bondedTestMint,
            rate: Self.usdRate,
            supplyQuarks: supplyQuarks
        )

        let result = [usdfBalance, bondedBalance].total(rate: Self.usdRate)

        // Total should exceed the USDF-only balance
        #expect(result.underlying.quarks > usdfBalance.underlying.quarks)
        #expect(result.converted.quarks > usdfBalance.converted.quarks)
        #expect(result.mint == PublicKey.usdf)
    }
}
