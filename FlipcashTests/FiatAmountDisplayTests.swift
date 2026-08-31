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
        "formattedAbbreviated(maxDigits:) caps the figure at three digits",
        arguments: [
            // currency, value, expected

            // Under the first scale — formatted as usual, fraction dropped when whole.
            (CurrencyCode.usd, Decimal(5),                    "$5"),
            (.usd,             Decimal(999),                  "$999"),
            (.usd,             Decimal(string: "12.50")!,     "$12.50"),

            // Thousands, with the cap deciding how many decimals survive.
            (.usd,             Decimal(1_000),                "$1K"),
            (.usd,             Decimal(1_500),                "$1.5K"),
            (.usd,             Decimal(1_234),                "$1.23K"),
            (.usd,             Decimal(12_345),               "$12.3K"),
            (.usd,             Decimal(123_456),              "$123K"),

            // Millions, billions and trillions get their own suffix.
            (.usd,             Decimal(1_000_000),            "$1M"),
            (.usd,             Decimal(2_500_000),            "$2.5M"),
            (.usd,             Decimal(1_000_000_000),        "$1B"),
            (.usd,             Decimal(1_000_000_000_000),    "$1T"),

            // An amount that rounds into the next scale is printed in that scale.
            (.usd,             Decimal(999_999),              "$1M"),

            (.usd,             Decimal(0),                    "$0"),

            // A zero-decimal currency abbreviates on the value, not its precision.
            (.jpy,             Decimal(750),                  "¥750"),
            (.jpy,             Decimal(3_000),                "¥3K"),

            // Small-unit currencies, where every everyday amount is four digits or
            // more — the case the tip presets abbreviate for. The ARS figures are
            // the $5 / $10 / $20 tiers in pesos.
            (.ars,             Decimal(7_500),                "$7.5K"),
            (.ars,             Decimal(15_000),               "$15K"),
            (.ars,             Decimal(30_000),               "$30K"),
            (.ars,             Decimal(25_500),               "$25.5K"),
            (.ars,             Decimal(123_456),              "$123K"),
            (.cop,             Decimal(97_500),               "$97.5K"),
            (.vnd,             Decimal(126_000),              "₫126K"),
            (.vnd,             Decimal(1_315_000),            "₫1.32M"),
            // IDR has no single-character symbol, so it formats bare.
            (.idr,             Decimal(332_000),              "332K"),
            (.idr,             Decimal(500),                  "500"),

            // Negatives keep the minus ahead of the symbol.
            (.usd,             Decimal(-1_500),               "-$1.5K"),
            (.usd,             Decimal(-2_400_000),           "-$2.4M"),
        ] as [(CurrencyCode, Decimal, String)]
    )
    func formattedAbbreviated(currency: CurrencyCode, value: Decimal, expected: String) {
        #expect(FiatAmount(value: value, currency: currency).formattedAbbreviated() == expected)
    }

    @Test("A lower cap allows fewer digits")
    func lowerCap() {
        #expect(FiatAmount.usd(1_234).formattedAbbreviated(maxDigits: 2) == "$1.2K")
    }
}
