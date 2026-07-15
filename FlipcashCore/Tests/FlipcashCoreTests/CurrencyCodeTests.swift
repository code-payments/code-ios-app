//
//  CurrencyCodeTests.swift
//  FlipcashCoreTests
//

import Testing
@testable import FlipcashCore

@Suite("CurrencyCode Tests")
struct CurrencyCodeTests {

    @Test("Compact symbol is the single-character locale symbol")
    func compactSymbol_symbolCurrency_returnsSingleCharacterSymbol() {
        #expect(CurrencyCode.eur.compactSymbol == "€")
        #expect(CurrencyCode.usd.compactSymbol == "$")
    }

    @Test("Compact symbol tie-break is deterministic")
    func compactSymbol_equalLengthSymbols_isDeterministic() {
        // JPY has two 1-char symbols across locales (¥ U+00A5, ￥ U+FFE5);
        // the lexicographic tie-break must always pick the same one.
        #expect(CurrencyCode.jpy.compactSymbol == "¥")
    }

    @Test("Compact symbol falls back to dollar sign")
    func compactSymbol_noSingleCharacterSymbol_fallsBackToDollarSign() {
        // CHF's locale symbols ("CHF", "Fr.") are all multi-character.
        #expect(CurrencyCode.chf.compactSymbol == "$")
    }

    @Test("Compact symbol is never empty")
    func compactSymbol_allCases_nonEmpty() {
        for currency in CurrencyCode.allCases {
            #expect(!currency.compactSymbol.isEmpty)
        }
    }
}
