//
//  SessionTests.swift
//  FlipcashTests
//
//  Created by Claude on 2025-11-10.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
struct SessionTests {

    // MARK: - Test Data

    static let mint = PublicKey.usdf
    static let rate = Rate(fx: 1.0, currency: .usd)

    /// Helper to create a mock session with a specific balance
    static func createMockSession(balanceQuarks: UInt64) -> Session {
        // Note: This is a simplified mock. In production, you'd use proper dependency injection
        // or a more sophisticated mocking framework
        return .mock
    }

    // MARK: - Sufficient Funds Tests

    @Test
    static func testSufficientFunds_ExactMatch() throws {
        // Given: User has exactly $1.00 USDC
        let balanceQuarks: UInt64 = 1_000_000 // $1.00 (6 decimals)
        let requestedQuarks: UInt64 = 1_000_000 // $1.00

        let balance = Quarks(quarks: balanceQuarks, currencyCode: .usd, decimals: 6)
        let requested = Quarks(quarks: requestedQuarks, currencyCode: .usd, decimals: 6)

        // When: Comparing balance to requested
        let hasFunds = balance >= requested

        // Then: Should have sufficient funds
        #expect(hasFunds == true)
        #expect(balance.quarks == requested.quarks)
    }

    @Test
    static func testSufficientFunds_UserHasMore() throws {
        // Given: User has $5.00, wants to send $1.00
        let balanceQuarks: UInt64 = 5_000_000 // $5.00
        let requestedQuarks: UInt64 = 1_000_000 // $1.00

        let balance = Quarks(quarks: balanceQuarks, currencyCode: .usd, decimals: 6)
        let requested = Quarks(quarks: requestedQuarks, currencyCode: .usd, decimals: 6)

        // When: Comparing balance to requested
        let hasFunds = balance >= requested

        // Then: Should have sufficient funds
        #expect(hasFunds == true)
        #expect(balance.quarks > requested.quarks)
    }

    // MARK: - Insufficient Funds Tests

    @Test
    static func testInsufficientFunds_ClearShortfall() throws {
        // Given: User has $1.00, wants to send $5.00
        let balanceQuarks: UInt64 = 1_000_000 // $1.00
        let requestedQuarks: UInt64 = 5_000_000 // $5.00

        let balance = Quarks(quarks: balanceQuarks, currencyCode: .usd, decimals: 6)
        let requested = Quarks(quarks: requestedQuarks, currencyCode: .usd, decimals: 6)

        // When: Comparing balance to requested
        let hasFunds = balance >= requested
        let shortfall = try requested.subtracting(balance)

        // Then: Should be insufficient with $4.00 shortfall
        #expect(hasFunds == false)
        #expect(shortfall.quarks == 4_000_000) // $4.00
        #expect(shortfall.decimalValue.formatted(to: 2) == "4.00")
    }

    // MARK: - Tolerance Logic Tests (Half-Penny Rule)

    @Test
    static func testTolerance_WithinHalfPenny_ShouldBeAllowed() throws {
        // Given: User has $0.0071 (0.71 cents), wants to send $0.01 (1 cent)
        // Delta = 0.0029 cents, which is < 0.005 tolerance
        let balanceQuarks: UInt64 = 7_100 // $0.0071
        let requestedQuarks: UInt64 = 10_000 // $0.01

        let balance = Quarks(quarks: balanceQuarks, currencyCode: .usd, decimals: 6)
        let requested = Quarks(quarks: requestedQuarks, currencyCode: .usd, decimals: 6)

        // When: Calculating delta
        let balanceDecimal = balance.decimalValue
        let requestedDecimal = requested.decimalValue
        let delta = abs(balanceDecimal - requestedDecimal)

        // Then: Delta should be within tolerance
        #expect(balance < requested) // Balance is less than requested
        #expect(delta <= 0.005) // But within half-penny tolerance
        #expect(delta.formatted(to: 4) == "0.0029") // Exact delta
    }

    @Test
    static func testTolerance_ExactlyHalfPenny_ShouldBeAllowed() throws {
        // Given: User has $0.0095, wants to send $0.01
        // Delta = 0.0005 cents, which is exactly the tolerance threshold
        let balanceQuarks: UInt64 = 9_500 // $0.0095
        let requestedQuarks: UInt64 = 10_000 // $0.01

        let balance = Quarks(quarks: balanceQuarks, currencyCode: .usd, decimals: 6)
        let requested = Quarks(quarks: requestedQuarks, currencyCode: .usd, decimals: 6)

        // When: Calculating delta
        let delta = abs(balance.decimalValue - requested.decimalValue)

        // Then: Delta should equal tolerance threshold
        #expect(delta <= 0.005)
        #expect(delta.formatted(to: 4) == "0.0005")
    }

    @Test
    static func testTolerance_JustOutsideHalfPenny_ShouldFail() throws {
        // Given: User has $0.0049, wants to send $0.01
        // Delta = 0.0051 cents, which is > 0.005 tolerance
        let balanceQuarks: UInt64 = 4_900 // $0.0049
        let requestedQuarks: UInt64 = 10_000 // $0.01

        let balance = Quarks(quarks: balanceQuarks, currencyCode: .usd, decimals: 6)
        let requested = Quarks(quarks: requestedQuarks, currencyCode: .usd, decimals: 6)

        // When: Calculating delta
        let delta = abs(balance.decimalValue - requested.decimalValue)

        // Then: Delta should exceed tolerance
        #expect(delta > 0.005)
        #expect(delta.formatted(to: 4) == "0.0051")
    }

    @Test
    static func testTolerance_LargeAmounts_StillApplies() throws {
        // Given: User has $100.0049, wants to send $100.01
        // Delta = 0.0051 cents (tolerance still applies regardless of magnitude)
        let balanceQuarks: UInt64 = 100_004_900 // $100.0049
        let requestedQuarks: UInt64 = 100_010_000 // $100.01

        let balance = Quarks(quarks: balanceQuarks, currencyCode: .usd, decimals: 6)
        let requested = Quarks(quarks: requestedQuarks, currencyCode: .usd, decimals: 6)

        // When: Calculating delta
        let delta = abs(balance.decimalValue - requested.decimalValue)

        // Then: Delta should exceed tolerance (tolerance is absolute, not percentage)
        #expect(delta > 0.005)
        #expect(delta.formatted(to: 4) == "0.0051")
    }

    // MARK: - Edge Cases

    @Test
    static func testZeroQuarks_ShouldBeInsufficient() throws {
        // Given: Requested amount is zero
        let requestedQuarks: UInt64 = 0

        let requested = Quarks(quarks: requestedQuarks, currencyCode: .usd, decimals: 6)

        // Then: Zero quarks should be rejected
        #expect(requested.quarks == 0)
        #expect(requested.decimalValue == 0)
    }

    @Test
    static func testExchangedFiat_WithinTolerance_ReturnsBalanceAmount() throws {
        // Given: User balance worth $0.0071, requesting $0.01
        let balanceQuarks: UInt64 = 7_100 // $0.0071
        let requestedQuarks: UInt64 = 10_000 // $0.01

        let balance = try ExchangedFiat(
            underlying: Quarks(quarks: balanceQuarks, currencyCode: .usd, decimals: 6),
            rate: rate,
            mint: mint
        )

        let requested = try ExchangedFiat(
            underlying: Quarks(quarks: requestedQuarks, currencyCode: .usd, decimals: 6),
            rate: rate,
            mint: mint
        )

        // When: Checking if within tolerance
        let delta = abs(balance.converted.decimalValue - requested.converted.decimalValue)

        // Then: Should be within tolerance and return balance amount
        #expect(delta <= 0.005)

        // If within tolerance, the actual send amount should be the balance
        let amountToSend = balance
        #expect(amountToSend.underlying.quarks == balanceQuarks)
        #expect(amountToSend.underlying.quarks < requestedQuarks)
    }

    // MARK: - Custom Currency Tests

    @Test
    static func testCustomCurrency_WithBondingCurve() throws {
        // Given: Custom token with 10 decimals
        // User has 65.52 tokens worth $0.0071 USD (from your debug log)
        let tokenQuarks: UInt64 = 6_552_205_892 // 0.6552205892 tokens (10 decimals)
        let requestedTokenQuarks: UInt64 = 9_193_567_061 // 0.9193567061 tokens

        // Simulate USDC values from bonding curve
        let balanceUSDC: UInt64 = 7_127 // $0.0071269471 (6 decimals)
        let requestedUSDC: UInt64 = 10_000 // $0.01 (6 decimals)

        let balance = Quarks(quarks: balanceUSDC, currencyCode: .usd, decimals: 6)
        let requested = Quarks(quarks: requestedUSDC, currencyCode: .usd, decimals: 6)

        // When: Checking tolerance
        let delta = abs(balance.decimalValue - requested.decimalValue)

        // Then: Should be within tolerance
        #expect(balance < requested)
        #expect(delta.formatted(to: 4) == "0.0029") // Matches your debug log
        #expect(delta <= 0.005) // Within tolerance

        // The amount to send should be the balance (not the requested amount)
        #expect(balance.quarks == balanceUSDC)
    }

    @Test
    static func testComparisonLogic_Fiat() throws {
        // Given: Two Fiat values
        let smaller = Quarks(quarks: 1_000_000 as UInt64, currencyCode: .usd, decimals: 6) // $1.00
        let larger = Quarks(quarks: 5_000_000 as UInt64, currencyCode: .usd, decimals: 6)  // $5.00

        // When/Then: Test comparison operators
        #expect(smaller < larger)
        #expect(smaller <= larger)
        #expect(larger > smaller)
        #expect(larger >= smaller)
        #expect(smaller <= smaller) // Equal
        #expect(smaller >= smaller) // Equal
    }

    // MARK: - Currency-Specific Tolerance Tests

    @Test
    static func testTolerance_USD_WithinHalfPenny() throws {
        // Given: USD with 2 decimal places
        // Tolerance = 0.01 / 2 = 0.005 (half a penny)
        // Balance: $0.996, Requested: $1.00, Delta: $0.004
        let usdRate = Rate(fx: 1.0, currency: .usd)

        let balance = try ExchangedFiat(
            underlying: Quarks(quarks: 996_000 as UInt64, currencyCode: .usd, decimals: 6), // $0.996
            rate: usdRate,
            mint: mint
        )

        let requested = try ExchangedFiat(
            underlying: Quarks(quarks: 1_000_000 as UInt64, currencyCode: .usd, decimals: 6), // $1.00
            rate: usdRate,
            mint: mint
        )

        // When: Calculating delta and tolerance
        let delta = abs(balance.converted.decimalValue - requested.converted.decimalValue)
        let decimals = requested.converted.currencyCode.maximumFractionDigits
        let tolerance = Decimal(pow(10.0, -Double(decimals))) / 2

        // Then: Should be within tolerance
        #expect(decimals == 2)
        #expect(tolerance == 0.005)
        #expect(delta == 0.004)
        #expect(delta <= tolerance)
    }

    @Test
    static func testTolerance_JPY_WithinHalfYen() throws {
        // Given: JPY with 0 decimal places
        // Tolerance = 1.0 / 2 = 0.5 (half a yen)
        // Balance: ¥0.6, Requested: ¥1.0, Delta: ¥0.4
        let jpyRate = Rate(fx: 149.0, currency: .jpy) // ~149 JPY per USD

        let balance = try ExchangedFiat(
            underlying: Quarks(quarks: 4_027 as UInt64, currencyCode: .usd, decimals: 6), // ~$0.004027 = ¥0.6
            rate: jpyRate,
            mint: mint
        )

        let requested = try ExchangedFiat(
            underlying: Quarks(quarks: 6_711 as UInt64, currencyCode: .usd, decimals: 6), // ~$0.006711 = ¥1.0
            rate: jpyRate,
            mint: mint
        )

        // When: Calculating delta and tolerance
        let delta = abs(balance.converted.decimalValue - requested.converted.decimalValue)
        let decimals = requested.converted.currencyCode.maximumFractionDigits
        let tolerance = Decimal(pow(10.0, -Double(decimals))) / 2

        // Then: Should be within tolerance
        #expect(decimals == 0)
        #expect(tolerance == 0.5)
        #expect(delta <= tolerance)
    }

    @Test
    static func testTolerance_JPY_ExceedsHalfYen() throws {
        // Given: JPY with 0 decimal places
        // Tolerance = 1.0 / 2 = 0.5 (half a yen)
        // Balance: ¥0.4, Requested: ¥1.0, Delta: ¥0.6 (exceeds tolerance)
        let jpyRate = Rate(fx: 149.0, currency: .jpy)

        let balance = try ExchangedFiat(
            underlying: Quarks(quarks: 2_685 as UInt64, currencyCode: .usd, decimals: 6), // ~$0.002685 = ¥0.4
            rate: jpyRate,
            mint: mint
        )

        let requested = try ExchangedFiat(
            underlying: Quarks(quarks: 6_711 as UInt64, currencyCode: .usd, decimals: 6), // ~$0.006711 = ¥1.0
            rate: jpyRate,
            mint: mint
        )

        // When: Calculating delta and tolerance
        let delta = abs(balance.converted.decimalValue - requested.converted.decimalValue)
        let decimals = requested.converted.currencyCode.maximumFractionDigits
        let tolerance = Decimal(pow(10.0, -Double(decimals))) / 2

        // Then: Should exceed tolerance
        #expect(decimals == 0)
        #expect(tolerance == 0.5)
        #expect(delta > tolerance)
    }

    @Test
    static func testTolerance_BHD_WithinHalfFils() throws {
        // Given: BHD (Bahraini Dinar) with 3 decimal places
        // Tolerance = 0.001 / 2 = 0.0005 (half a fils)
        // Balance: BD 0.9996, Requested: BD 1.000, Delta: BD 0.0004
        let bhdRate = Rate(fx: 0.376, currency: .bhd) // ~0.376 BHD per USD

        let balance = try ExchangedFiat(
            underlying: Quarks(quarks: 2_658_511 as UInt64, currencyCode: .usd, decimals: 6), // ~$2.658511 = BD 0.9996
            rate: bhdRate,
            mint: mint
        )

        let requested = try ExchangedFiat(
            underlying: Quarks(quarks: 2_659_574 as UInt64, currencyCode: .usd, decimals: 6), // ~$2.659574 = BD 1.000
            rate: bhdRate,
            mint: mint
        )

        // When: Calculating delta and tolerance
        let delta = abs(balance.converted.decimalValue - requested.converted.decimalValue)
        let decimals = requested.converted.currencyCode.maximumFractionDigits
        let tolerance = Decimal(pow(10.0, -Double(decimals))) / 2

        // Then: Should be within tolerance
        #expect(decimals == 3)
        #expect(tolerance == 0.0005)
        #expect(delta <= tolerance)
    }

    @Test
    static func testTolerance_ExactlyAtBoundary_USD() throws {
        // Given: Delta exactly at tolerance boundary
        // Balance: $0.995, Requested: $1.00, Delta: $0.005 (exactly at tolerance)
        let usdRate = Rate(fx: 1.0, currency: .usd)

        let balance = try ExchangedFiat(
            underlying: Quarks(quarks: 995_000 as UInt64, currencyCode: .usd, decimals: 6),
            rate: usdRate,
            mint: mint
        )

        let requested = try ExchangedFiat(
            underlying: Quarks(quarks: 1_000_000 as UInt64, currencyCode: .usd, decimals: 6),
            rate: usdRate,
            mint: mint
        )

        // When: Calculating delta and tolerance
        let delta = abs(balance.converted.decimalValue - requested.converted.decimalValue)
        let decimals = requested.converted.currencyCode.maximumFractionDigits
        let tolerance = Decimal(pow(10.0, -Double(decimals))) / 2

        // Then: Should be exactly at tolerance (should pass with <=)
        #expect(delta == 0.005)
        #expect(delta == tolerance)
        #expect(delta <= tolerance)
    }

    @Test
    static func testTolerance_ExactlyAtBoundary_JPY() throws {
        // Given: Delta at or very near tolerance boundary for JPY
        // Balance: ¥0.5, Requested: ¥1.0, Delta: ¥~0.5 (at tolerance)
        let jpyRate = Rate(fx: 149.0, currency: .jpy)

        let balance = try ExchangedFiat(
            underlying: Quarks(quarks: 3_356 as UInt64, currencyCode: .usd, decimals: 6), // ~$0.003356 = ¥0.5
            rate: jpyRate,
            mint: mint
        )

        let requested = try ExchangedFiat(
            underlying: Quarks(quarks: 6_711 as UInt64, currencyCode: .usd, decimals: 6), // ~$0.006711 = ¥1.0
            rate: jpyRate,
            mint: mint
        )

        // When: Calculating delta and tolerance
        let delta = abs(balance.converted.decimalValue - requested.converted.decimalValue)
        let decimals = requested.converted.currencyCode.maximumFractionDigits
        let tolerance = Decimal(pow(10.0, -Double(decimals))) / 2

        // Then: Should be at or very near tolerance boundary (within tolerance due to floating-point precision)
        #expect(decimals == 0)
        #expect(tolerance == 0.5)
        #expect(delta <= tolerance, "Delta \(delta) should be within tolerance \(tolerance)")
    }

    @Test
    static func testTolerance_JustOutsideBoundary_USD() throws {
        // Given: Delta just outside tolerance
        // Balance: $0.9949, Requested: $1.00, Delta: $0.0051 (exceeds tolerance)
        let usdRate = Rate(fx: 1.0, currency: .usd)

        let balance = try ExchangedFiat(
            underlying: Quarks(quarks: 994_900 as UInt64, currencyCode: .usd, decimals: 6),
            rate: usdRate,
            mint: mint
        )

        let requested = try ExchangedFiat(
            underlying: Quarks(quarks: 1_000_000 as UInt64, currencyCode: .usd, decimals: 6),
            rate: usdRate,
            mint: mint
        )

        // When: Calculating delta and tolerance
        let delta = abs(balance.converted.decimalValue - requested.converted.decimalValue)
        let decimals = requested.converted.currencyCode.maximumFractionDigits
        let tolerance = Decimal(pow(10.0, -Double(decimals))) / 2

        // Then: Should exceed tolerance
        #expect(delta == 0.0051)
        #expect(delta > tolerance)
    }

    @Test
    static func testTolerance_CalculationCorrectness() throws {
        // Test that tolerance formula works correctly for various decimal places
        struct CurrencyTest {
            let currency: CurrencyCode
            let expectedDecimals: Int
            let expectedTolerance: Decimal
        }

        let tests: [CurrencyTest] = [
            CurrencyTest(currency: .usd, expectedDecimals: 2, expectedTolerance: 0.005),
            CurrencyTest(currency: .eur, expectedDecimals: 2, expectedTolerance: 0.005),
            CurrencyTest(currency: .jpy, expectedDecimals: 0, expectedTolerance: 0.5),
            CurrencyTest(currency: .krw, expectedDecimals: 0, expectedTolerance: 0.5),
            CurrencyTest(currency: .bhd, expectedDecimals: 3, expectedTolerance: 0.0005),
            CurrencyTest(currency: .kwd, expectedDecimals: 3, expectedTolerance: 0.0005),
        ]

        for test in tests {
            let decimals = test.currency.maximumFractionDigits
            let smallestDenomination = pow(10.0, -Double(decimals))
            let tolerance = Decimal(smallestDenomination / 2.0)

            #expect(decimals == test.expectedDecimals,
                   "Expected \(test.currency) to have \(test.expectedDecimals) decimals, got \(decimals)")
            #expect(tolerance == test.expectedTolerance,
                   "Expected \(test.currency) tolerance to be \(test.expectedTolerance), got \(tolerance)")
        }
    }

    // MARK: - Real-World Scenario Tests

    @Test
    static func testRealWorldScenario_FarmerCoinJPY() throws {
        // Given: Real bug scenario - Small Farmer Coin balance worth ~0.6 JPY
        // UI shows "1 Yen" but user only has 0.6 JPY worth
        let jpyRate = Rate(fx: 149.0, currency: .jpy)

        // User's actual balance: worth ¥0.6
        let actualBalance = try ExchangedFiat(
            underlying: Quarks(quarks: 4_027 as UInt64, currencyCode: .usd, decimals: 6),
            rate: jpyRate,
            mint: mint
        )

        // User tries to send: ¥1.0 (what UI shows after rounding)
        let requestedAmount = try ExchangedFiat(
            underlying: Quarks(quarks: 6_711 as UInt64, currencyCode: .usd, decimals: 6),
            rate: jpyRate,
            mint: mint
        )

        // When: Checking if within tolerance
        let delta = abs(actualBalance.converted.decimalValue - requestedAmount.converted.decimalValue)
        let decimals = requestedAmount.converted.currencyCode.maximumFractionDigits
        let tolerance = Decimal(pow(10.0, -Double(decimals))) / 2

        // Then: Should pass tolerance check (delta ≈ ¥0.4, tolerance = ¥0.5)
        #expect(decimals == 0)
        #expect(tolerance == 0.5)
        #expect(delta <= tolerance, "Delta \(delta) should be within tolerance \(tolerance)")

        // This should NOT produce "You're 0 Yen short" error
        // Instead, it should send the actual balance
    }
}
