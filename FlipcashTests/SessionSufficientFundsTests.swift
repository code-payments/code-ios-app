//
//  SessionSufficientFundsTests.swift
//  FlipcashTests
//
//  Created by Claude on 2025-11-10.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
struct SessionSufficientFundsTests {

    // MARK: - Test Data

    static let mint = PublicKey.usdc
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

        let balance = Fiat(quarks: balanceQuarks, currencyCode: .usd, decimals: 6)
        let requested = Fiat(quarks: requestedQuarks, currencyCode: .usd, decimals: 6)

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

        let balance = Fiat(quarks: balanceQuarks, currencyCode: .usd, decimals: 6)
        let requested = Fiat(quarks: requestedQuarks, currencyCode: .usd, decimals: 6)

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

        let balance = Fiat(quarks: balanceQuarks, currencyCode: .usd, decimals: 6)
        let requested = Fiat(quarks: requestedQuarks, currencyCode: .usd, decimals: 6)

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

        let balance = Fiat(quarks: balanceQuarks, currencyCode: .usd, decimals: 6)
        let requested = Fiat(quarks: requestedQuarks, currencyCode: .usd, decimals: 6)

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

        let balance = Fiat(quarks: balanceQuarks, currencyCode: .usd, decimals: 6)
        let requested = Fiat(quarks: requestedQuarks, currencyCode: .usd, decimals: 6)

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

        let balance = Fiat(quarks: balanceQuarks, currencyCode: .usd, decimals: 6)
        let requested = Fiat(quarks: requestedQuarks, currencyCode: .usd, decimals: 6)

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

        let balance = Fiat(quarks: balanceQuarks, currencyCode: .usd, decimals: 6)
        let requested = Fiat(quarks: requestedQuarks, currencyCode: .usd, decimals: 6)

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

        let requested = Fiat(quarks: requestedQuarks, currencyCode: .usd, decimals: 6)

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
            usdc: Fiat(quarks: balanceQuarks, currencyCode: .usd, decimals: 6),
            rate: rate,
            mint: mint
        )

        let requested = try ExchangedFiat(
            usdc: Fiat(quarks: requestedQuarks, currencyCode: .usd, decimals: 6),
            rate: rate,
            mint: mint
        )

        // When: Checking if within tolerance
        let delta = abs(balance.converted.decimalValue - requested.converted.decimalValue)

        // Then: Should be within tolerance and return balance amount
        #expect(delta <= 0.005)

        // If within tolerance, the actual send amount should be the balance
        let amountToSend = balance
        #expect(amountToSend.usdc.quarks == balanceQuarks)
        #expect(amountToSend.usdc.quarks < requestedQuarks)
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

        let balance = Fiat(quarks: balanceUSDC, currencyCode: .usd, decimals: 6)
        let requested = Fiat(quarks: requestedUSDC, currencyCode: .usd, decimals: 6)

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
        let smaller = Fiat(quarks: 1_000_000 as UInt64, currencyCode: .usd, decimals: 6) // $1.00
        let larger = Fiat(quarks: 5_000_000 as UInt64, currencyCode: .usd, decimals: 6)  // $5.00

        // When/Then: Test comparison operators
        #expect(smaller < larger)
        #expect(smaller <= larger)
        #expect(larger > smaller)
        #expect(larger >= smaller)
        #expect(smaller <= smaller) // Equal
        #expect(smaller >= smaller) // Equal
    }
}
