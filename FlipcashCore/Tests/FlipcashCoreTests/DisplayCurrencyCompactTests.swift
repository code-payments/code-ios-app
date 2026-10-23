//
//  DisplayCurrencyCompactTests.swift
//  FlipcashCoreTests
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("DisplayCurrency compact market figures")
struct DisplayCurrencyCompactTests {

    @Test("A USD market cap is restated in the display currency")
    func restatesInDisplayCurrency() {
        let display = DisplayCurrency(currency: .cad, rates: [Rate(fx: 1.4, currency: .cad)])

        #expect(display.compactFormatted(usd: 1_000_000) == CompactCurrencyFormatStyle(code: .cad).format(1_400_000))
        #expect(display.compactFormatted(usd: -10_000) == CompactCurrencyFormatStyle(code: .cad).format(-14_000))
    }

    @Test("USD display leaves the figure as it is")
    func usdDisplay() {
        let display = DisplayCurrency(currency: .usd, rates: [Rate(fx: 1.4, currency: .cad)])

        #expect(display.compactFormatted(usd: 1_029_331.15) == "$1.03M")
    }

    @Test("With no rate for the display currency the USD figure is shown bare")
    func noRate() {
        let display = DisplayCurrency(currency: .eur, rates: [Rate(fx: 1.4, currency: .cad)])

        #expect(display.compactFormatted(usd: 48_200) == "$48.2K")
    }
}
