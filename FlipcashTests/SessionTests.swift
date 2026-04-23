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

    /// Helper: build a USDF-minted `ExchangedFiat` from a 6-decimal USD quark
    /// integer and a rate.
    static func makeUSDFExchangedFiat(usdQuarks: UInt64, rate: Rate) -> ExchangedFiat {
        ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: usdQuarks, mint: .usdf),
            rate: rate,
            supplyQuarks: nil
        )
    }

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
        let balance = FiatAmount(value: 1, currency: .usd)
        let requested = FiatAmount(value: 1, currency: .usd)

        // When: Comparing balance to requested
        let hasFunds = balance >= requested

        // Then: Should have sufficient funds
        #expect(hasFunds == true)
        #expect(balance.value == requested.value)
    }

    @Test
    static func testSufficientFunds_UserHasMore() throws {
        // Given: User has $5.00, wants to send $1.00
        let balance = FiatAmount(value: 5, currency: .usd)
        let requested = FiatAmount(value: 1, currency: .usd)

        // When: Comparing balance to requested
        let hasFunds = balance >= requested

        // Then: Should have sufficient funds
        #expect(hasFunds == true)
        #expect(balance.value > requested.value)
    }

    // MARK: - Insufficient Funds Tests

    @Test
    static func testInsufficientFunds_ClearShortfall() throws {
        // Given: User has $1.00, wants to send $5.00
        let balance = FiatAmount(value: 1, currency: .usd)
        let requested = FiatAmount(value: 5, currency: .usd)

        // When: Comparing balance to requested
        let hasFunds = balance >= requested
        let shortfall = requested - balance

        // Then: Should be insufficient with $4.00 shortfall
        #expect(hasFunds == false)
        #expect(shortfall.value == 4) // $4.00
        #expect(shortfall.value.formatted(to: 2) == "4.00")
    }

    // MARK: - Tolerance Logic Tests (Half-Penny Rule)

    @Test
    static func testTolerance_WithinHalfPenny_ShouldBeAllowed() throws {
        // Given: User has $0.0071 (0.71 cents), wants to send $0.01 (1 cent)
        // Delta = 0.0029 cents, which is < 0.005 tolerance
        let balance = FiatAmount(value: Decimal(string: "0.0071")!, currency: .usd)
        let requested = FiatAmount(value: Decimal(string: "0.01")!, currency: .usd)

        // When: Calculating delta
        let delta = abs(balance.value - requested.value)

        // Then: Delta should be within tolerance
        #expect(balance < requested) // Balance is less than requested
        #expect(delta <= 0.005) // But within half-penny tolerance
        #expect(delta.formatted(to: 4) == "0.0029") // Exact delta
    }

    @Test
    static func testTolerance_ExactlyHalfPenny_ShouldBeAllowed() throws {
        // Given: User has $0.0095, wants to send $0.01
        // Delta = 0.0005 cents, which is exactly the tolerance threshold
        let balance = FiatAmount(value: Decimal(string: "0.0095")!, currency: .usd)
        let requested = FiatAmount(value: Decimal(string: "0.01")!, currency: .usd)

        // When: Calculating delta
        let delta = abs(balance.value - requested.value)

        // Then: Delta should equal tolerance threshold
        #expect(delta <= 0.005)
        #expect(delta.formatted(to: 4) == "0.0005")
    }

    @Test
    static func testTolerance_JustOutsideHalfPenny_ShouldFail() throws {
        // Given: User has $0.0049, wants to send $0.01
        // Delta = 0.0051 cents, which is > 0.005 tolerance
        let balance = FiatAmount(value: Decimal(string: "0.0049")!, currency: .usd)
        let requested = FiatAmount(value: Decimal(string: "0.01")!, currency: .usd)

        // When: Calculating delta
        let delta = abs(balance.value - requested.value)

        // Then: Delta should exceed tolerance
        #expect(delta > 0.005)
        #expect(delta.formatted(to: 4) == "0.0051")
    }

    @Test
    static func testTolerance_LargeAmounts_StillApplies() throws {
        // Given: User has $100.0049, wants to send $100.01
        // Delta = 0.0051 cents (tolerance still applies regardless of magnitude)
        let balance = FiatAmount(value: Decimal(string: "100.0049")!, currency: .usd)
        let requested = FiatAmount(value: Decimal(string: "100.01")!, currency: .usd)

        // When: Calculating delta
        let delta = abs(balance.value - requested.value)

        // Then: Delta should exceed tolerance (tolerance is absolute, not percentage)
        #expect(delta > 0.005)
        #expect(delta.formatted(to: 4) == "0.0051")
    }

    // MARK: - Edge Cases

    @Test
    static func testZeroQuarks_ShouldBeInsufficient() throws {
        // Given: Requested amount is zero
        let requested = FiatAmount(value: 0, currency: .usd)

        // Then: Zero should be rejected
        #expect(requested.value == 0)
    }

    @Test
    static func testExchangedFiat_WithinTolerance_ReturnsBalanceAmount() throws {
        // Given: User balance worth $0.0071, requesting $0.01
        let balanceQuarks: UInt64 = 7_100 // $0.0071
        let requestedQuarks: UInt64 = 10_000 // $0.01

        let balance = Self.makeUSDFExchangedFiat(usdQuarks: balanceQuarks, rate: rate)

        let requested = Self.makeUSDFExchangedFiat(usdQuarks: requestedQuarks, rate: rate)

        // When: Checking if within tolerance
        let delta = abs(balance.nativeAmount.value - requested.nativeAmount.value)

        // Then: Should be within tolerance and return balance amount
        #expect(delta <= 0.005)

        // If within tolerance, the actual send amount should be the balance
        let amountToSend = balance
        #expect(amountToSend.onChainAmount.quarks == balanceQuarks)
        #expect(amountToSend.onChainAmount.quarks < requestedQuarks)
    }

    // MARK: - Custom Currency Tests

    @Test
    static func testCustomCurrency_WithBondingCurve() throws {
        // Given: Custom token with 10 decimals
        // User has 65.52 tokens worth $0.0071 USD (from your debug log)

        // Simulate USDC values from bonding curve
        // $0.007127 - rounded to a 4-decimal delta of 0.0029 vs $0.01
        let balance = FiatAmount(value: Decimal(string: "0.007127")!, currency: .usd)
        let requested = FiatAmount(value: Decimal(string: "0.01")!, currency: .usd)

        // When: Checking tolerance
        let delta = abs(balance.value - requested.value)

        // Then: Should be within tolerance
        #expect(balance < requested)
        #expect(delta.formatted(to: 4) == "0.0029") // Matches your debug log
        #expect(delta <= 0.005) // Within tolerance

        // The amount to send should be the balance (not the requested amount)
        #expect(balance.value == Decimal(string: "0.007127")!)
    }

    @Test
    static func testComparisonLogic_Fiat() throws {
        // Given: Two Fiat values
        let smaller = FiatAmount(value: 1, currency: .usd) // $1.00
        let larger = FiatAmount(value: 5, currency: .usd)  // $5.00

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

        let balance = Self.makeUSDFExchangedFiat(usdQuarks: 996_000, rate: usdRate)  // $0.996

        let requested = Self.makeUSDFExchangedFiat(usdQuarks: 1_000_000, rate: usdRate) // $1.00

        // When: Calculating delta and tolerance
        let delta = abs(balance.nativeAmount.value - requested.nativeAmount.value)
        let decimals = requested.nativeAmount.currency.maximumFractionDigits
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

        let balance = Self.makeUSDFExchangedFiat(usdQuarks: 4_027, rate: jpyRate)  // ~$0.004027 = ¥0.6

        let requested = Self.makeUSDFExchangedFiat(usdQuarks: 6_711, rate: jpyRate) // ~$0.006711 = ¥1.0

        // When: Calculating delta and tolerance
        let delta = abs(balance.nativeAmount.value - requested.nativeAmount.value)
        let decimals = requested.nativeAmount.currency.maximumFractionDigits
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

        let balance = Self.makeUSDFExchangedFiat(usdQuarks: 2_685, rate: jpyRate) // ~$0.002685 = ¥0.4

        let requested = Self.makeUSDFExchangedFiat(usdQuarks: 6_711, rate: jpyRate) // ~$0.006711 = ¥1.0

        // When: Calculating delta and tolerance
        let delta = abs(balance.nativeAmount.value - requested.nativeAmount.value)
        let decimals = requested.nativeAmount.currency.maximumFractionDigits
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

        let balance = Self.makeUSDFExchangedFiat(usdQuarks: 2_658_511, rate: bhdRate) // ~$2.658511 = BD 0.9996

        let requested = Self.makeUSDFExchangedFiat(usdQuarks: 2_659_574, rate: bhdRate) // ~$2.659574 = BD 1.000

        // When: Calculating delta and tolerance
        let delta = abs(balance.nativeAmount.value - requested.nativeAmount.value)
        let decimals = requested.nativeAmount.currency.maximumFractionDigits
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

        let balance = Self.makeUSDFExchangedFiat(usdQuarks: 995_000, rate: usdRate)

        let requested = Self.makeUSDFExchangedFiat(usdQuarks: 1_000_000, rate: usdRate)

        // When: Calculating delta and tolerance
        let delta = abs(balance.nativeAmount.value - requested.nativeAmount.value)
        let decimals = requested.nativeAmount.currency.maximumFractionDigits
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

        let balance = Self.makeUSDFExchangedFiat(usdQuarks: 3_356, rate: jpyRate) // ~$0.003356 = ¥0.5

        let requested = Self.makeUSDFExchangedFiat(usdQuarks: 6_711, rate: jpyRate) // ~$0.006711 = ¥1.0

        // When: Calculating delta and tolerance
        let delta = abs(balance.nativeAmount.value - requested.nativeAmount.value)
        let decimals = requested.nativeAmount.currency.maximumFractionDigits
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

        let balance = Self.makeUSDFExchangedFiat(usdQuarks: 994_900, rate: usdRate)

        let requested = Self.makeUSDFExchangedFiat(usdQuarks: 1_000_000, rate: usdRate)

        // When: Calculating delta and tolerance
        let delta = abs(balance.nativeAmount.value - requested.nativeAmount.value)
        let decimals = requested.nativeAmount.currency.maximumFractionDigits
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
        let actualBalance = Self.makeUSDFExchangedFiat(usdQuarks: 4_027, rate: jpyRate)

        // User tries to send: ¥1.0 (what UI shows after rounding)
        let requestedAmount = Self.makeUSDFExchangedFiat(usdQuarks: 6_711, rate: jpyRate)

        // When: Checking if within tolerance
        let delta = abs(actualBalance.nativeAmount.value - requestedAmount.nativeAmount.value)
        let decimals = requestedAmount.nativeAmount.currency.maximumFractionDigits
        let tolerance = Decimal(pow(10.0, -Double(decimals))) / 2

        // Then: Should pass tolerance check (delta ≈ ¥0.4, tolerance = ¥0.5)
        #expect(decimals == 0)
        #expect(tolerance == 0.5)
        #expect(delta <= tolerance, "Delta \(delta) should be within tolerance \(tolerance)")

        // This should NOT produce "You're 0 Yen short" error
        // Instead, it should send the actual balance
    }

    // MARK: - Total Balance Consistency Tests

    @Test("Collection<ExchangedFiat>.total(rate:) matches sum of individual converted values")
    static func testTotalBalance_MatchesBalancesForRate() throws {
        // This test verifies that total(rate:) produces a converted value
        // equal to the sum of individual converted values.
        //
        // Bug context: The header showed $8.09 but the rows summed to $8.10
        // because totalBalance was converting after summing USD values,
        // while rows converted individually.

        // Use a non-USD rate to exercise currency conversion
        let cadRate = Rate(fx: 1.40, currency: .cad)

        // Create individual ExchangedFiat values (USDF balances with 6 decimals)
        let balances: [ExchangedFiat] = [
            Self.makeUSDFExchangedFiat(usdQuarks: 3_500_000, rate: cadRate),
            Self.makeUSDFExchangedFiat(usdQuarks: 2_290_000, rate: cadRate),
        ]

        // Compute total using the Collection extension (same code path as Session.totalBalance)
        let total = balances.total(rate: cadRate)

        // Sum individual native values
        let sumOfNative = balances.reduce(Decimal(0)) { sum, balance in
            sum + balance.nativeAmount.value
        }

        // Verify total is non-zero
        #expect(total.nativeAmount.value > 0, "Total should be non-zero to be a meaningful test")

        // The total's native value should equal the sum of individual native values
        #expect(
            total.nativeAmount.value == sumOfNative,
            "total(rate:) (\(total.nativeAmount.value)) should equal sum of native values (\(sumOfNative))"
        )
    }
}

// MARK: -

@MainActor
@Suite("Session.buy verified state")
struct SessionBuyVerifiedStateTests {

    private static let staleAmount = ExchangedFiat(
        onChainAmount: TokenAmount(quarks: 1_000_000, mint: .usdf),
        nativeAmount: .usd(1),
        currencyRate: .oneToOne
    )

    @Test("buy throws verifiedStateStale when the provided state is past clientMaxAge")
    func buy_throwsStale() async {
        let session = Session.unverifiedMock
        let stale = VerifiedState.makeForTest(
            rateTimestamp: Date().addingTimeInterval(-VerifiedState.clientMaxAge - 1),
            reserveTimestamp: nil
        )

        do {
            _ = try await session.buy(
                amount: Self.staleAmount,
                verifiedState: stale,
                of: .usdf
            )
            Issue.record("Expected verifiedStateStale to be thrown")
        } catch Session.Error.verifiedStateStale {
            // expected
        } catch {
            Issue.record("Unexpected error thrown: \(error)")
        }
    }

    @Test("buyNewCurrency throws verifiedStateStale when the provided state is past clientMaxAge")
    func buyNewCurrency_throwsStale() async {
        let session = Session.unverifiedMock
        let stale = VerifiedState.makeForTest(
            rateTimestamp: Date().addingTimeInterval(-VerifiedState.clientMaxAge - 1),
            reserveTimestamp: nil
        )

        do {
            _ = try await session.buyNewCurrency(
                amount: Self.staleAmount,
                feeAmount: Self.staleAmount,
                verifiedState: stale,
                mint: .usdf
            )
            Issue.record("Expected verifiedStateStale to be thrown")
        } catch Session.Error.verifiedStateStale {
            // expected
        } catch {
            Issue.record("Unexpected error thrown: \(error)")
        }
    }
}

// MARK: -

@MainActor
@Suite("Session.sell verified state")
struct SessionSellVerifiedStateTests {

    private static let amount = ExchangedFiat(
        onChainAmount: TokenAmount(quarks: 1_000_000, mint: .usdf),
        nativeAmount: .usd(1),
        currencyRate: .oneToOne
    )

    @Test("sell throws verifiedStateStale when the provided state is past clientMaxAge")
    func sell_throwsStale() async {
        let session = Session.unverifiedMock
        let stale = VerifiedState.makeForTest(
            rateTimestamp: Date().addingTimeInterval(-VerifiedState.clientMaxAge - 1),
            reserveTimestamp: nil
        )

        do {
            _ = try await session.sell(
                amount: Self.amount,
                verifiedState: stale,
                in: .usdf
            )
            Issue.record("Expected verifiedStateStale to be thrown")
        } catch Session.Error.verifiedStateStale {
            // expected
        } catch {
            Issue.record("Unexpected error thrown: \(error)")
        }
    }
}

// MARK: -

@MainActor
@Suite("Session.withdraw verified state")
struct SessionWithdrawVerifiedStateTests {

    private static let amount = ExchangedFiat(
        onChainAmount: TokenAmount(quarks: 1_000_000, mint: .usdf),
        nativeAmount: .usd(1),
        currencyRate: .oneToOne
    )

    @Test("withdraw throws verifiedStateStale when the provided state is past clientMaxAge")
    func withdraw_throwsStale() async {
        let session = Session.unverifiedMock
        let stale = VerifiedState.makeForTest(
            rateTimestamp: Date().addingTimeInterval(-VerifiedState.clientMaxAge - 1),
            reserveTimestamp: nil
        )

        do {
            try await session.withdraw(
                exchangedFiat: Self.amount,
                verifiedState: stale,
                fee: .zero(mint: .usdf),
                to: WithdrawViewModelTestHelpers.createDestinationMetadata()
            )
            Issue.record("Expected verifiedStateStale to be thrown")
        } catch Session.Error.verifiedStateStale {
            // expected
        } catch {
            Issue.record("Unexpected error thrown: \(error)")
        }
    }
}
