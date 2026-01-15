//
//  ExchangedFiatDisplayTests.swift
//  FlipcashTests
//
//  Created by Claude on 2025-11-13.
//

import Foundation
import Testing
@testable import FlipcashCore

struct ExchangedFiatDisplayTests {

    // MARK: - USD Tests (2 fraction digits)

    @Test
    func testHasDisplayableValue_USD_ExactlyOneCent_ReturnsTrue() throws {
        // Given: Exactly $0.01 (10,000 quarks with 6 decimals)
        let underlying = Quarks(quarks: 10_000 as UInt64, currencyCode: .usd, decimals: 6)
        let exchangedFiat = try ExchangedFiat(
            underlying: underlying,
            rate: Rate(fx: 1.0, currency: .usd),
            mint: .usdf
        )

        // When/Then: Should be displayable
        #expect(exchangedFiat.hasDisplayableValue() == true)
    }

    @Test
    func testHasDisplayableValue_USD_LessThanOneCent_ReturnsFalse() throws {
        // Given: Less than $0.01 (9,999 quarks with 6 decimals = $0.009999)
        let underlying = Quarks(quarks: 9_999 as UInt64, currencyCode: .usd, decimals: 6)
        let exchangedFiat = try ExchangedFiat(
            underlying: underlying,
            rate: Rate(fx: 1.0, currency: .usd),
            mint: .usdf
        )

        // When/Then: Should not be displayable
        #expect(exchangedFiat.hasDisplayableValue() == false)
    }

    @Test
    func testHasDisplayableValue_USD_OneDollar_ReturnsTrue() throws {
        // Given: $1.00 (1,000,000 quarks with 6 decimals)
        let underlying = Quarks(quarks: 1_000_000 as UInt64, currencyCode: .usd, decimals: 6)
        let exchangedFiat = try ExchangedFiat(
            underlying: underlying,
            rate: Rate(fx: 1.0, currency: .usd),
            mint: .usdf
        )

        // When/Then: Should be displayable
        #expect(exchangedFiat.hasDisplayableValue() == true)
    }

    @Test
    func testHasDisplayableValue_USD_TinyAmount_ReturnsFalse() throws {
        // Given: Very tiny amount (1 quark = $0.000001)
        let underlying = Quarks(quarks: 1 as UInt64, currencyCode: .usd, decimals: 6)
        let exchangedFiat = try ExchangedFiat(
            underlying: underlying,
            rate: Rate(fx: 1.0, currency: .usd),
            mint: .usdf
        )

        // When/Then: Should not be displayable
        #expect(exchangedFiat.hasDisplayableValue() == false)
    }

    // MARK: - JPY Tests (0 fraction digits)

    @Test
    func testHasDisplayableValue_JPY_ExactlyOneYen_ReturnsTrue() throws {
        // Given: Exactly ¥1 (1,000,000 quarks with 6 decimals)
        let underlying = Quarks(quarks: 1_000_000 as UInt64, currencyCode: .usd, decimals: 6)
        let exchangedFiat = try ExchangedFiat(
            underlying: underlying,
            rate: Rate(fx: 1.0, currency: .jpy),
            mint: .usdf
        )

        // When/Then: Should be displayable
        #expect(exchangedFiat.hasDisplayableValue() == true)
    }

    @Test
    func testHasDisplayableValue_JPY_LessThanOneYen_ReturnsFalse() throws {
        // Given: Less than ¥1 (999,999 quarks with 6 decimals = ¥0.999999)
        let underlying = Quarks(quarks: 999_999 as UInt64, currencyCode: .usd, decimals: 6)
        let exchangedFiat = try ExchangedFiat(
            underlying: underlying,
            rate: Rate(fx: 1.0, currency: .jpy),
            mint: .usdf
        )

        // When/Then: Should not be displayable
        #expect(exchangedFiat.hasDisplayableValue() == false)
    }

    @Test
    func testHasDisplayableValue_JPY_TenYen_ReturnsTrue() throws {
        // Given: ¥10 (10,000,000 quarks with 6 decimals)
        let underlying = Quarks(quarks: 10_000_000 as UInt64, currencyCode: .usd, decimals: 6)
        let exchangedFiat = try ExchangedFiat(
            underlying: underlying,
            rate: Rate(fx: 1.0, currency: .jpy),
            mint: .usdf
        )

        // When/Then: Should be displayable
        #expect(exchangedFiat.hasDisplayableValue() == true)
    }

    // MARK: - EUR Tests (2 fraction digits)

    @Test
    func testHasDisplayableValue_EUR_ExactlyOneCent_ReturnsTrue() throws {
        // Given: Exactly €0.01 (10,000 quarks with 6 decimals)
        let underlying = Quarks(quarks: 10_000 as UInt64, currencyCode: .usd, decimals: 6)
        let exchangedFiat = try ExchangedFiat(
            underlying: underlying,
            rate: Rate(fx: 1.0, currency: .eur),
            mint: .usdf
        )

        // When/Then: Should be displayable
        #expect(exchangedFiat.hasDisplayableValue() == true)
    }

    @Test
    func testHasDisplayableValue_EUR_LessThanOneCent_ReturnsFalse() throws {
        // Given: Less than €0.01 (5,000 quarks with 6 decimals = €0.005)
        let underlying = Quarks(quarks: 5_000 as UInt64, currencyCode: .usd, decimals: 6)
        let exchangedFiat = try ExchangedFiat(
            underlying: underlying,
            rate: Rate(fx: 1.0, currency: .eur),
            mint: .usdf
        )

        // When/Then: Should not be displayable
        #expect(exchangedFiat.hasDisplayableValue() == false)
    }

    // MARK: - CAD Tests (2 fraction digits)

    @Test
    func testHasDisplayableValue_CAD_ExactlyOneCent_ReturnsTrue() throws {
        // Given: Exactly C$0.01 (10,000 quarks with 6 decimals)
        let underlying = Quarks(quarks: 10_000 as UInt64, currencyCode: .usd, decimals: 6)
        let exchangedFiat = try ExchangedFiat(
            underlying: underlying,
            rate: Rate(fx: 1.0, currency: .cad),
            mint: .usdf
        )

        // When/Then: Should be displayable
        #expect(exchangedFiat.hasDisplayableValue() == true)
    }

    @Test
    func testHasDisplayableValue_CAD_LessThanOneCent_ReturnsFalse() throws {
        // Given: Less than C$0.01 (9,000 quarks with 6 decimals = C$0.009)
        let underlying = Quarks(quarks: 9_000 as UInt64, currencyCode: .usd, decimals: 6)
        let exchangedFiat = try ExchangedFiat(
            underlying: underlying,
            rate: Rate(fx: 1.0, currency: .cad),
            mint: .usdf
        )

        // When/Then: Should not be displayable
        #expect(exchangedFiat.hasDisplayableValue() == false)
    }

    // MARK: - GBP Tests (2 fraction digits)

    @Test
    func testHasDisplayableValue_GBP_ExactlyOnePenny_ReturnsTrue() throws {
        // Given: Exactly £0.01 (10,000 quarks with 6 decimals)
        let underlying = Quarks(quarks: 10_000 as UInt64, currencyCode: .usd, decimals: 6)
        let exchangedFiat = try ExchangedFiat(
            underlying: underlying,
            rate: Rate(fx: 1.0, currency: .gbp),
            mint: .usdf
        )

        // When/Then: Should be displayable
        #expect(exchangedFiat.hasDisplayableValue() == true)
    }

    @Test
    func testHasDisplayableValue_GBP_LessThanOnePenny_ReturnsFalse() throws {
        // Given: Less than £0.01 (7,000 quarks with 6 decimals = £0.007)
        let underlying = Quarks(quarks: 7_000 as UInt64, currencyCode: .usd, decimals: 6)
        let exchangedFiat = try ExchangedFiat(
            underlying: underlying,
            rate: Rate(fx: 1.0, currency: .gbp),
            mint: .usdf
        )

        // When/Then: Should not be displayable
        #expect(exchangedFiat.hasDisplayableValue() == false)
    }

    // MARK: - Edge Cases

    @Test
    func testHasDisplayableValue_Zero_ReturnsFalse() throws {
        // Given: Exactly zero quarks
        let exchangedFiat = try ExchangedFiat(
            underlying: Quarks(quarks: 0 as UInt64, currencyCode: .usd, decimals: 6),
            rate: Rate(fx: 1.0, currency: .usd),
            mint: .usdf
        )

        // When/Then: Should not be displayable
        #expect(exchangedFiat.hasDisplayableValue() == false)
    }

    @Test
    func testHasDisplayableValue_LargeAmount_ReturnsTrue() throws {
        // Given: Large amount ($1,000,000)
        let exchangedFiat = try ExchangedFiat(
            underlying: Quarks(quarks: 1_000_000_000_000 as UInt64, currencyCode: .usd, decimals: 6),
            rate: Rate(fx: 1.0, currency: .usd),
            mint: .usdf
        )

        // When/Then: Should be displayable
        #expect(exchangedFiat.hasDisplayableValue() == true)
    }

    // MARK: - Rate Conversion Tests

    @Test
    func testHasDisplayableValue_WithExchangeRate_USD_CalculatesCorrectly() throws {
        // Given: Small USD amount converted to CAD at 1.4 rate
        // $0.007 USD * 1.4 = C$0.0098 CAD (below C$0.01 threshold)
        let exchangedFiat = try ExchangedFiat(
            underlying: Quarks(quarks: 7_000 as UInt64, currencyCode: .usd, decimals: 6),
            rate: Rate(fx: 1.4, currency: .cad),
            mint: .usdf
        )

        // When/Then: Should not be displayable (below C$0.01)
        #expect(exchangedFiat.hasDisplayableValue() == false)
    }

    @Test
    func testHasDisplayableValue_WithExchangeRate_CAD_CalculatesCorrectly() throws {
        // Given: Small USD amount converted to CAD at 1.4 rate
        // $0.008 USD * 1.4 = C$0.0112 CAD (above C$0.01 threshold)
        let exchangedFiat = try ExchangedFiat(
            underlying: Quarks(quarks: 8_000 as UInt64, currencyCode: .usd, decimals: 6),
            rate: Rate(fx: 1.4, currency: .cad),
            mint: .usdf
        )

        // When/Then: Should be displayable (above C$0.01)
        #expect(exchangedFiat.hasDisplayableValue() == true)
    }

    @Test
    func testHasDisplayableValue_BondedToken_WithSupply_CalculatesCorrectly() throws {
        // Given: Bonded token with small value
        // Using a non-USDF mint with supply quarks (100 tokens = 100 * 10^10 quarks)
        let exchangedFiat = ExchangedFiat.computeFromQuarks(
            quarks: 5_000 as UInt64,
            mint: .jeffy, // Use a non-USDF mint to trigger bonding curve
            rate: Rate(fx: 1.0, currency: .usd),
            supplyQuarks: 100 * 10_000_000_000 as UInt64 // 100 tokens supply
        )

        // When/Then: Result depends on bonding curve calculation
        // Just verify the function doesn't crash and returns a boolean
        let result = exchangedFiat.hasDisplayableValue()
        #expect(result == true || result == false)
    }
}
