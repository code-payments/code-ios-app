//
//  FiatAmountFormattedTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("FiatAmount Formatted")
struct FiatAmountFormattedTests {

    // MARK: - Default precision

    @Test("USD whole number defaults to two fractional digits")
    func formatted_USD_wholeNumber_default_showsTrailingZeros() {
        #expect(FiatAmount.usd(10).formatted() == "$10.00")
    }

    @Test("USD fractional value at default precision keeps two digits")
    func formatted_USD_fractional_default_keepsTwoDigits() {
        #expect(FiatAmount.usd(Decimal(string: "10.5")!).formatted() == "$10.50")
    }

    @Test("USD zero defaults to two fractional digits")
    func formatted_USD_zero_default_showsTrailingZeros() {
        #expect(FiatAmount.usd(0).formatted() == "$0.00")
    }

    // MARK: - minimumFractionDigits override

    @Test("USD whole number with minimumFractionDigits 0 strips trailing zeros")
    func formatted_USD_wholeNumber_minimumFractionDigitsZero_stripsTrailingZeros() {
        #expect(FiatAmount.usd(10).formatted(minimumFractionDigits: 0) == "$10")
    }

    @Test("USD half-dollar value with minimumFractionDigits 0 strips trailing zero")
    func formatted_USD_halfDollar_minimumFractionDigitsZero_stripsTrailingZero() {
        #expect(FiatAmount.usd(Decimal(string: "10.5")!).formatted(minimumFractionDigits: 0) == "$10.5")
    }

    @Test("USD penny value with minimumFractionDigits 0 keeps two decimals")
    func formatted_USD_penny_minimumFractionDigitsZero_keepsDecimals() {
        #expect(FiatAmount.usd(Decimal(string: "10.01")!).formatted(minimumFractionDigits: 0) == "$10.01")
    }

    @Test("USD zero with minimumFractionDigits 0 strips trailing zeros")
    func formatted_USD_zero_minimumFractionDigitsZero_stripsTrailingZeros() {
        #expect(FiatAmount.usd(0).formatted(minimumFractionDigits: 0) == "$0")
    }

    @Test("USD with minimumFractionDigits 1 always shows one decimal")
    func formatted_USD_wholeNumber_minimumFractionDigitsOne_showsSingleDecimal() {
        #expect(FiatAmount.usd(10).formatted(minimumFractionDigits: 1) == "$10.0")
    }

    // MARK: - Suffix

    @Test("Suffix is appended after the amount")
    func formatted_USD_withSuffix_appendsAfterAmount() {
        #expect(FiatAmount.usd(10).formatted(minimumFractionDigits: 0, suffix: " USD") == "$10 USD")
    }

    @Test("Suffix and default precision combine")
    func formatted_USD_suffixOnly_keepsDefaultPrecision() {
        #expect(FiatAmount.usd(10).formatted(suffix: " USD") == "$10.00 USD")
    }

    // MARK: - Explicit nil matches default

    @Test("Explicit nil minimumFractionDigits matches the omitted-argument default")
    func formatted_USD_explicitNil_matchesDefault() {
        let amount = FiatAmount.usd(10)
        #expect(amount.formatted(minimumFractionDigits: nil) == amount.formatted())
    }
}
