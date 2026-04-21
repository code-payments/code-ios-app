//
//  Regression_sell_jpy_red_limit.swift
//  Flipcash
//
//  Bug: The "Enter up to ¥X" subtitle in the sell flow turns red even when
//       the entered amount is well within the limit.
//
//  Cause: isWithinDisplayLimit round-tripped the max amount through
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

    @Test("JPY amount within balance is accepted")
    func jpyWithinBalance() {
        let max = FiatAmount(value: 1_218, currency: .jpy)
        #expect(EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: "1", max: max) == true)
    }

    @Test("JPY amount equal to balance is accepted")
    func jpyEqualToBalance() {
        let max = FiatAmount(value: 1_218, currency: .jpy)
        #expect(EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: "1218", max: max) == true)
    }

    @Test("JPY amount exceeding balance is rejected")
    func jpyExceedingBalance() {
        let max = FiatAmount(value: 1_218, currency: .jpy)
        #expect(EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: "1219", max: max) == false)
    }

    @Test(
        "Non-USD currencies with single-character symbols are parsed correctly",
        arguments: [CurrencyCode.jpy, .gbp, .krw, .cny, .inr, .try]
    )
    func nonUSDCurrencies_withinLimit(currency: CurrencyCode) {
        let max = FiatAmount(value: 10_000, currency: currency)
        #expect(EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: "1", max: max) == true)
    }
}
