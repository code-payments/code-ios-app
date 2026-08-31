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

    // MARK: - Rounding to the smallest unit

    @Test("Rounding takes a value up once it passes the half-unit")
    func rounding_roundsHalfUp() {
        let amount = FiatAmount.usd(Decimal(string: "9.906")!)

        #expect(amount.roundedToSmallestUnit().value == Decimal(string: "9.91")!)
    }

    @Test("Rounding drops sub-unit precision below the half-unit")
    func rounding_dropsSubUnitPrecision() {
        let amount = FiatAmount.usd(Decimal(string: "9.90099")!)

        #expect(amount.roundedToSmallestUnit().value == Decimal(string: "9.90")!)
    }

    @Test("Rounding leaves a value already on the smallest unit untouched")
    func rounding_exactValue_unchanged() {
        let exact = FiatAmount.usd(Decimal(string: "9.90")!)

        #expect(exact.roundedToSmallestUnit() == exact)
    }

    @Test("Rounding a zero-decimal currency rounds to whole units")
    func rounding_zeroDecimalCurrency_roundsToWholeUnits() {
        let yen = FiatAmount(value: Decimal(string: "1234.9")!, currency: .jpy)

        #expect(yen.roundedToSmallestUnit().value == 1235)
    }

    @Test("Two values that display alike round to the same figure")
    func rounding_valuesSharingADisplayedFigure_collapse() {
        // The wallet card stack compares at this precision so a sixth-decimal
        // move can't reorder two cards that both read $1.00.
        let under = FiatAmount.usd(Decimal(string: "0.9996")!)
        let over  = FiatAmount.usd(Decimal(string: "1.0004")!)

        #expect(under.roundedToSmallestUnit() == over.roundedToSmallestUnit())
    }
}
