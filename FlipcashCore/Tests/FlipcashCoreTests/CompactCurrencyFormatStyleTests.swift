//
//  CompactCurrencyFormatStyleTests.swift
//  FlipcashCoreTests
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("CompactCurrencyFormatStyle")
struct CompactCurrencyFormatStyleTests {

    let format = CompactCurrencyFormatStyle(code: .usd)

    @Test("Millions are formatted with M suffix")
    func millions() {
        #expect(format.format(1_000_000) == "$1M")
        #expect(format.format(1_029_331.15) == "$1M")
        #expect(format.format(1_299_217.10) == "$1.3M")
        #expect(format.format(10_500_000) == "$10M")
    }

    @Test("Thousands are formatted with K suffix")
    func thousands() {
        #expect(format.format(690_272.45) == "$690K")
        #expect(format.format(211_282.93) == "$211K")
        #expect(format.format(100_000) == "$100K")
    }

    @Test("Small values use compact notation")
    func smallValues() {
        #expect(format.format(99_999) == "$100K")
        #expect(format.format(1_234) == "$1.2K")
        #expect(format.format(200.17) == "$200")
    }

    @Test("Zero formats correctly")
    func zero() {
        #expect(format.format(0) == "$0")
    }

    @Test("Currency symbol uses CurrencyCode")
    func currencySymbol() {
        let eurFormat = CompactCurrencyFormatStyle(code: .eur)
        #expect(eurFormat.format(1_000_000).contains("1M"))
    }

    @Test("Works with Text format syntax")
    func formatStyleExtension() {
        let result = 1_029_331.15.formatted(.compactCurrency(code: .usd))
        #expect(result == "$1M")
    }
}
