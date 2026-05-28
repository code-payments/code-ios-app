//
//  FiatAmountFormattedTests.swift
//  FlipcashTests
//
//  Assertions in this file depend on the simulator running with an
//  `en_US`-style locale (`.` decimal separator, `,` grouping separator).
//  `NumberFormatter.fiat` reads `Locale.current` for separators; the
//  currency prefix is locale-stable via
//  `CurrencyCode.singleCharacterCurrencySymbols`.
//

import Foundation
import Testing
@testable import FlipcashCore

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
