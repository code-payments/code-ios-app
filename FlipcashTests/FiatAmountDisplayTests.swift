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
