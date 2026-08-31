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
        // Half-up, like every other displayed figure — ICU's compact notation
        // rounded this half-even to "$10M".
        #expect(format.format(10_500_000) == "$11M")
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
        // Under a thousand the figure is shown whole — sub-unit precision is
        // dropped rather than rounded into the display.
        #expect(format.format(200.17) == "$200")
        #expect(format.format(999.99) == "$999")
    }

    @Test("Negative values put the sign before the currency symbol")
    func negativeValues() {
        #expect(format.format(-12_400) == "-$12K")
        #expect(format.format(-6_600) == "-$6.6K")
        #expect(format.format(-384) == "-$384")
        #expect(format.format(-1_299_217.10) == "-$1.3M")
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
