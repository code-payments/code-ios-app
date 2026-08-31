//
//  FiatAmountDisplayTests.swift
//  FlipcashTests
//
//  Assertions on `formatted()` strings depend on the simulator running
//  with an `en_US`-style locale (`.` decimal separator, `,` grouping
//  separator). `NumberFormatter.fiat` reads `Locale.current` for
//  separators; the currency prefix is locale-stable via
//  `CurrencyCode.singleCharacterCurrencySymbols`.
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("FiatAmount Display Threshold")
struct FiatAmountDisplayTests {

    // MARK: - hasDisplayableValue

    @Test("USD exactly one cent is displayable")
    func hasDisplayableValue_USD_exactlyOneCent() {
        let amount = FiatAmount(value: Decimal(string: "0.01")!, currency: .usd)
        #expect(amount.hasDisplayableValue == true)
    }

    @Test("USD less than one cent is not displayable")
    func hasDisplayableValue_USD_lessThanOneCent() {
        let amount = FiatAmount(value: Decimal(string: "0.009999")!, currency: .usd)
        #expect(amount.hasDisplayableValue == false)
    }

    @Test("USD one dollar is displayable")
    func hasDisplayableValue_USD_oneDollar() {
        let amount = FiatAmount(value: 1, currency: .usd)
        #expect(amount.hasDisplayableValue == true)
    }

    @Test("USD tiny sub-cent value is not displayable")
    func hasDisplayableValue_USD_subCent() {
        let amount = FiatAmount(value: Decimal(string: "0.000001")!, currency: .usd)
        #expect(amount.hasDisplayableValue == false)
    }

    @Test("JPY exactly one yen is displayable")
    func hasDisplayableValue_JPY_exactlyOneYen() {
        let amount = FiatAmount(value: 1, currency: .jpy)
        #expect(amount.hasDisplayableValue == true)
    }

    @Test("JPY less than one yen is not displayable")
    func hasDisplayableValue_JPY_lessThanOneYen() {
        let amount = FiatAmount(value: Decimal(string: "0.999999")!, currency: .jpy)
        #expect(amount.hasDisplayableValue == false)
    }

    @Test("EUR less than one cent is not displayable")
    func hasDisplayableValue_EUR_lessThanOneCent() {
        let amount = FiatAmount(value: Decimal(string: "0.005")!, currency: .eur)
        #expect(amount.hasDisplayableValue == false)
    }

    @Test("GBP exactly one penny is displayable")
    func hasDisplayableValue_GBP_exactlyOnePenny() {
        let amount = FiatAmount(value: Decimal(string: "0.01")!, currency: .gbp)
        #expect(amount.hasDisplayableValue == true)
    }

    @Test("Zero is not displayable")
    func hasDisplayableValue_zero() {
        let amount = FiatAmount(value: 0, currency: .usd)
        #expect(amount.hasDisplayableValue == false)
    }

    @Test("Large amount is displayable")
    func hasDisplayableValue_largeAmount() {
        let amount = FiatAmount(value: 1_000_000, currency: .usd)
        #expect(amount.hasDisplayableValue == true)
    }

    // MARK: - isApproximatelyZero

    @Test("USD sub-cent is approximately zero")
    func isApproximatelyZero_USD_subCent() {
        let amount = FiatAmount(value: Decimal(string: "0.000001")!, currency: .usd)
        #expect(amount.isApproximatelyZero == true)
    }

    @Test("USD exactly one cent is not approximately zero")
    func isApproximatelyZero_USD_exactlyOneCent() {
        let amount = FiatAmount(value: Decimal(string: "0.01")!, currency: .usd)
        #expect(amount.isApproximatelyZero == false)
    }

    @Test("Zero is not approximately zero")
    func isApproximatelyZero_zero() {
        let amount = FiatAmount(value: 0, currency: .usd)
        #expect(amount.isApproximatelyZero == false)
    }

    @Test("JPY sub-yen is approximately zero")
    func isApproximatelyZero_JPY_subYen() {
        let amount = FiatAmount(value: Decimal(string: "0.999999")!, currency: .jpy)
        #expect(amount.isApproximatelyZero == true)
    }
}

@Suite("FiatAmount Formatted")
struct FiatAmountFormattedTests {

    @Test(
        "formatted(minimumFractionDigits:suffix:) renders the expected string",
        arguments: [
            // currency, value,                       minFrac, suffix,  expected

            // USD — default precision
            (CurrencyCode.usd, Decimal(10),               nil,     nil,     "$10.00"),
            (.usd,             Decimal(string: "10.5")!,  nil,     nil,     "$10.50"),
            (.usd,             Decimal(0),                nil,     nil,     "$0.00"),
            (.usd,             Decimal(string: "1.23456")!, nil,   nil,     "$1.23"),   // rounds halfUp

            // USD — minimumFractionDigits override
            (.usd,             Decimal(10),               Int?(0), nil,     "$10"),
            (.usd,             Decimal(string: "10.5")!,  Int?(0), nil,     "$10.5"),   // trailing zero stripped
            (.usd,             Decimal(string: "10.01")!, Int?(0), nil,     "$10.01"),  // preserves cents
            (.usd,             Decimal(0),                Int?(0), nil,     "$0"),
            (.usd,             Decimal(10),               Int?(1), nil,     "$10.0"),

            // USD — suffix
            (.usd,             Decimal(10),               Int?(0), " USD",  "$10 USD"),
            (.usd,             Decimal(10),               nil,     " USD",  "$10.00 USD"),

            // JPY — zero-decimal currency: never shows fractional digits regardless
            // of the FiatAmount's underlying precision.
            (.jpy,             Decimal(1000),             nil,     nil,     "¥1,000"),
            (.jpy,             Decimal(10),               nil,     nil,     "¥10"),
            (.jpy,             Decimal(string: "10.5")!,  nil,     nil,     "¥11"),     // halfUp

            // Negatives — the minus leads the currency symbol.
            (.usd,             Decimal(-10),              nil,     nil,     "-$10.00"),
            (.usd,             Decimal(string: "-10.5")!, Int?(0), nil,     "-$10.5"),
            (.usd,             Decimal(-10),              Int?(0), " USD",  "-$10 USD"),
            (.jpy,             Decimal(-1000),            nil,     nil,     "-¥1,000"),
        ] as [(CurrencyCode, Decimal, Int?, String?, String)]
    )
    func formatted(currency: CurrencyCode, value: Decimal, minimumFractionDigits: Int?, suffix: String?, expected: String) {
        #expect(
            FiatAmount(value: value, currency: currency).formatted(
                minimumFractionDigits: minimumFractionDigits,
                suffix: suffix
            ) == expected
        )
    }
}

@Suite("FiatAmount Abbreviated")
struct FiatAmountAbbreviatedTests {

    @Test(
        "formattedAbbreviated(minimumFractionDigits:) keeps the figure to three digits",
        arguments: [
            // currency, value,                        minFrac, expected

            // Under a thousand — plain formatting, untouched.
            (CurrencyCode.usd, Decimal(1),                 Int?(0), "$1"),
            (.usd,             Decimal(999),               Int?(0), "$999"),
            (.usd,             Decimal(string: "2.50")!,   nil,     "$2.50"),
            (.usd,             Decimal(999),               nil,     "$999.00"),

            // Thousands — a decimal only while the figure is a single digit.
            (.usd,             Decimal(1_000),             Int?(0), "$1K"),
            (.usd,             Decimal(1_500),             Int?(0), "$1.5K"),
            (.usd,             Decimal(1_550),             Int?(0), "$1.6K"),   // halfUp
            (.usd,             Decimal(9_999),             Int?(0), "$10K"),
            (.usd,             Decimal(15_000),            Int?(0), "$15K"),
            (.usd,             Decimal(150_000),           Int?(0), "$150K"),
            (.usd,             Decimal(999_499),           Int?(0), "$999K"),

            // The rounding carry: 999.5K is a fourth digit, so it becomes $1M.
            (.usd,             Decimal(999_500),           Int?(0), "$1M"),

            // Millions and billions.
            (.usd,             Decimal(2_400_000),         Int?(0), "$2.4M"),
            (.usd,             Decimal(25_000_000),        Int?(0), "$25M"),
            (.usd,             Decimal(1_000_000_000),     Int?(0), "$1B"),
            (.usd,             Decimal(1_250_000_000),     Int?(0), "$1.3B"),

            // Past the largest scale there is nowhere to carry, so it stays in B.
            (.usd,             Decimal(1_000_000_000_000), Int?(0), "$1,000B"),

            // A zero-decimal currency abbreviates on the value, not its precision.
            (.jpy,             Decimal(1_500),             Int?(0), "¥1.5K"),
            (.jpy,             Decimal(250_000),           Int?(0), "¥250K"),

            // Small-unit currencies, where every everyday amount is four digits
            // or more — the case the tip presets abbreviate for. ARS values are
            // roughly the $1 / $25 / $1,000 tiers.
            (.ars,             Decimal(1_400),             Int?(0), "$1.4K"),
            (.ars,             Decimal(35_000),            Int?(0), "$35K"),
            (.ars,             Decimal(1_400_000),         Int?(0), "$1.4M"),
            (.cop,             Decimal(97_500),            Int?(0), "$98K"),
            (.vnd,             Decimal(650_000),           Int?(0), "₫650K"),
            // IDR has no single-character symbol, so it formats bare.
            (.idr,             Decimal(400_000),           Int?(0), "400K"),

            // Negatives keep the minus ahead of the symbol.
            (.usd,             Decimal(-1_500),            Int?(0), "-$1.5K"),
            (.usd,             Decimal(-2_400_000),        Int?(0), "-$2.4M"),
        ] as [(CurrencyCode, Decimal, Int?, String)]
    )
    func formattedAbbreviated(currency: CurrencyCode, value: Decimal, minimumFractionDigits: Int?, expected: String) {
        #expect(
            FiatAmount(value: value, currency: currency)
                .formattedAbbreviated(minimumFractionDigits: minimumFractionDigits) == expected
        )
    }
}
