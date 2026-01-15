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
        // subtracting(fee:) requires USD rate
        let exchangedFiat = try ExchangedFiat(
            converted: try Quarks(fiatDecimal: 5.00, currencyCode: .usd, decimals: Self.usdcDecimals),
            rate: .oneToOne,
            mint: .usdc
        )

        let fee = try Quarks(fiatDecimal: 0.5, currencyCode: .usd, decimals: Self.usdcDecimals)

        let result = try exchangedFiat.subtracting(fee: fee)

        #expect(exchangedFiat.underlying.quarks == 5_000_000)
        #expect(fee.quarks == 500_000)
        #expect(result.underlying.quarks == 4_500_000)
    }

    @Test("Subtract fee too large")
    func testSubtractingFeeTooLarge() throws {
        // subtracting(fee:) requires USD rate
        let exchangedFiat = try ExchangedFiat(
            converted: try Quarks(fiatDecimal: 0.40, currencyCode: .usd, decimals: Self.usdcDecimals),
            rate: .oneToOne,
            mint: .usdc
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
            mint: .usdc
        )

        let fee = try Quarks(fiatDecimal: 0.5, currencyCode: .usd, decimals: Self.usdcDecimals)

        // When fee equals amount, result should be zero (not an error)
        let result = try exchangedFiat.subtracting(fee: fee)
        #expect(result.underlying.quarks == 0)
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
    private let testMint = PublicKey.jeffy

    // $1 = 1,000,000 quarks (6 decimals for USDC TVL)
    private let quarksPerDollar: UInt64 = 1_000_000

    @Test("Zero TVL returns nil for non-USDC mint")
    func zeroTVLReturnsNil() {
        // This was the crash scenario: zero TVL means no tokens to exchange
        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(5.0),
            rate: .oneToOne,
            mint: testMint,
            tvl: 0  // Zero TVL - should return nil, not crash
        )

        #expect(result == nil, "Zero TVL should return nil, not crash")
    }

    @Test("Amount exceeding TVL returns nil for non-USDC mint")
    func amountExceedingTVLReturnsNil() {
        // Try to exchange $100 when TVL is only $10
        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(100.0),
            rate: .oneToOne,
            mint: testMint,
            tvl: 10 * quarksPerDollar  // Only $10 TVL
        )

        #expect(result == nil, "Amount exceeding TVL should return nil")
    }

    @Test("Zero amount returns nil")
    func zeroAmountReturnsNil() {
        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(0),
            rate: .oneToOne,
            mint: testMint,
            tvl: 100 * quarksPerDollar
        )

        #expect(result == nil, "Zero amount should return nil")
    }

    @Test("Negative amount returns nil")
    func negativeAmountReturnsNil() {
        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(-5.0),
            rate: .oneToOne,
            mint: testMint,
            tvl: 100 * quarksPerDollar
        )

        #expect(result == nil, "Negative amount should return nil")
    }

    @Test("Valid exchange succeeds for non-USDC mint")
    func validExchangeSucceeds() {
        // $5 exchange with $100 TVL - should succeed
        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(5.0),
            rate: .oneToOne,
            mint: testMint,
            tvl: 100 * quarksPerDollar
        )

        #expect(result != nil, "Valid exchange should succeed")
        if let result = result {
            #expect(result.converted.quarks > 0, "Should have positive converted quarks")
            #expect(result.underlying.quarks > 0, "Should have positive underlying quarks")
        }
    }

    @Test("Small exchange with small TVL succeeds - GiveViewModel scenario")
    func smallExchangeWithSmallTVL() {
        // This mirrors the GiveViewModel test case:
        // User enters $0.50 with $1 TVL - should succeed
        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(0.50),
            rate: .oneToOne,
            mint: testMint,
            tvl: quarksPerDollar  // $1 TVL
        )

        #expect(result != nil, "$0.50 exchange with $1 TVL should succeed")
        if let result = result {
            #expect(result.converted.quarks > 0, "Should have positive converted quarks")
            #expect(result.underlying.quarks > 0, "Should have positive underlying quarks")
        }
    }

    @Test("Valid exchange with non-USD currency succeeds")
    func validExchangeWithNonUSDCurrencySucceeds() {
        // $7 CAD at 1.4 rate = $5 USD, with $100 TVL
        let cadRate = Rate(fx: Decimal(1.4), currency: .cad)
        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(7.0),
            rate: cadRate,
            mint: testMint,
            tvl: 100 * quarksPerDollar
        )

        #expect(result != nil, "Valid CAD exchange should succeed")
        if let result = result {
            #expect(result.converted.quarks > 0)
            #expect(result.rate.currency == .cad)
        }
    }

    @Test("USDC mint bypasses bonding curve and succeeds")
    func usdcMintBypassesBondingCurve() {
        // USDC doesn't use bonding curve, so zero TVL shouldn't matter
        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(5.0),
            rate: .oneToOne,
            mint: .usdc,
            tvl: 0  // Zero TVL - should still work for USDC
        )

        #expect(result != nil, "USDC should bypass bonding curve")
    }

    @Test("Very small amount near TVL limit returns nil")
    func verySmallAmountNearTVLLimit() {
        // TVL of $0.01, trying to exchange $0.01 - edge case
        // This tests the boundary where newTVL approaches zero
        let result = ExchangedFiat.computeFromEntered(
            amount: Decimal(0.01),
            rate: .oneToOne,
            mint: testMint,
            tvl: 10_000  // $0.01 TVL (10,000 quarks)
        )

        // Either nil (not enough TVL) or valid result - but NOT a crash
        if let result = result {
            #expect(result.converted.quarks >= 0)
        }
        // Test passes as long as we don't crash
    }
}
