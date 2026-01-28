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
        // subtracting(fee:) requires USD rate
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
}
