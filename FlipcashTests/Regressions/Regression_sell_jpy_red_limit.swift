//
//  Regression_sell_jpy_red_limit.swift
//  Flipcash
//
//  Bug: The "Enter up to ¥X" subtitle in the sell flow turns red even when
//       the entered amount is well within the limit.
//
//  Cause: isWithinDisplayLimit round-tripped the max Quarks through
//         formatted() → NumberFormatter.decimal(from:). The generic
//         parsers only recognise the device locale's currency symbol,
//         so "¥1,218" fails to parse on an en_US device → displayMax
//         falls back to 0 → any positive amount is treated as exceeding.
//
//  Fix: Parse the formatted string back using the same currency-aware
//       formatter that produced it.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Regression: sell flow JPY limit shown as exceeded")
struct Regression_sell_jpy_red_limit {

    @Test("JPY amount within balance is accepted (custom token, 10 decimals)")
    func jpyWithinBalance_customToken() {
        // ¥1,218 at 10 decimals (custom token mint)
        let max = Quarks(quarks: 12_180_000_000_000 as UInt64, currencyCode: .jpy, decimals: 10)
        #expect(EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: "1", max: max) == true)
    }

    @Test("JPY amount equal to balance is accepted")
    func jpyEqualToBalance() {
        let max = Quarks(quarks: 12_180_000_000_000 as UInt64, currencyCode: .jpy, decimals: 10)
        #expect(EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: "1218", max: max) == true)
    }

    @Test("JPY amount exceeding balance is rejected")
    func jpyExceedingBalance() {
        let max = Quarks(quarks: 12_180_000_000_000 as UInt64, currencyCode: .jpy, decimals: 10)
        #expect(EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: "1219", max: max) == false)
    }

    @Test("JPY amount within balance is accepted (USDF, 6 decimals)")
    func jpyWithinBalance_usdf() {
        // ¥1,218 at 6 decimals
        let max = Quarks(quarks: 1_218_000_000 as UInt64, currencyCode: .jpy, decimals: 6)
        #expect(EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: "500", max: max) == true)
    }

    @Test(
        "Non-USD currencies with single-character symbols are parsed correctly",
        arguments: [CurrencyCode.jpy, .gbp, .krw, .cny, .inr, .try]
    )
    func nonUSDCurrencies_withinLimit(currency: CurrencyCode) {
        let max = Quarks(quarks: 10_000_000_000 as UInt64, currencyCode: currency, decimals: 6)
        #expect(EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: "1", max: max) == true)
    }
}
