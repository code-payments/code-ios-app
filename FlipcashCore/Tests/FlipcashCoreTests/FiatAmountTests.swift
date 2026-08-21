//
//  FiatAmountTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("FiatAmount")
struct FiatAmountTests {

    // MARK: - Flooring to the smallest unit

    @Test("Flooring truncates sub-unit precision instead of rounding it up")
    func flooring_truncatesRatherThanRounds() {
        // Leaving 1% headroom on a $10.00 balance gives $9.90099 — rounding up
        // would put the entry right back over budget.
        let floored = FiatAmount.usd(Decimal(string: "9.90099")!).flooredToSmallestUnit()

        #expect(floored.value == Decimal(string: "9.90")!)
    }

    @Test("Flooring leaves a value already on the smallest unit untouched")
    func flooring_exactValue_unchanged() {
        let exact = FiatAmount.usd(Decimal(string: "9.90")!)

        #expect(exact.flooredToSmallestUnit() == exact)
    }

    @Test("Flooring a zero-decimal currency truncates to whole units")
    func flooring_zeroDecimalCurrency_truncatesToWholeUnits() {
        let yen = FiatAmount(value: Decimal(string: "1234.9")!, currency: .jpy)

        #expect(yen.flooredToSmallestUnit().value == 1234)
    }
}
