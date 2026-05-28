//
//  FiatAmountFormattedTests.swift
//  FlipcashTests
//
//  Assertions in this file depend on the simulator running with an
//  `en_US`-style locale (`.` decimal separator). `NumberFormatter.fiat`
//  reads `Locale.current` for the decimal separator; the `$` prefix is
//  locale-stable via `CurrencyCode.singleCharacterCurrencySymbols`.
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("FiatAmount Formatted")
struct FiatAmountFormattedTests {

    @Test(
        "formatted(minimumFractionDigits:suffix:) renders the expected string",
        arguments: [
            // value,                    minFrac, suffix,   expected
            (Decimal(10),                nil,     nil,      "$10.00"),
            (Decimal(string: "10.5")!,   nil,     nil,      "$10.50"),
            (Decimal(0),                 nil,     nil,      "$0.00"),
            (Decimal(10),                Int?(0), nil,      "$10"),
            (Decimal(string: "10.5")!,   Int?(0), nil,      "$10.5"),
            (Decimal(string: "10.01")!,  Int?(0), nil,      "$10.01"),
            (Decimal(0),                 Int?(0), nil,      "$0"),
            (Decimal(10),                Int?(1), nil,      "$10.0"),
            (Decimal(10),                Int?(0), " USD",   "$10 USD"),
            (Decimal(10),                nil,     " USD",   "$10.00 USD"),
        ] as [(Decimal, Int?, String?, String)]
    )
    func formatted_USD(value: Decimal, minimumFractionDigits: Int?, suffix: String?, expected: String) {
        #expect(
            FiatAmount.usd(value).formatted(
                minimumFractionDigits: minimumFractionDigits,
                suffix: suffix
            ) == expected
        )
    }
}
