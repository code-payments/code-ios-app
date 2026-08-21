//
//  FeeAffordableEntryTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("Fee-affordable entry")
struct FeeAffordableEntryTests {

    private func usd(_ value: String) -> FiatAmount {
        FiatAmount.usd(Decimal(string: value)!)
    }

    // MARK: - Entries that already fit

    @Test("An entry with room for its fee is left exactly as typed")
    func entryWithRoom_isLeftAlone() {
        #expect(entryAffordableAfterFee(
            entered: 5,
            balance: usd("10.00"),
            feeBps: 100,
            feeChargedOnTop: true
        ) == nil)
    }

    @Test("A free conversion never corrects the entry")
    func zeroFee_neverCorrects() {
        #expect(entryAffordableAfterFee(
            entered: 10,
            balance: usd("10.00"),
            feeBps: 0,
            feeChargedOnTop: true
        ) == nil)
    }

    // MARK: - Entering the maximum

    @Test("The whole balance drops to what a fee charged on top leaves")
    func wholeBalance_feeOnTop() throws {
        let corrected = try #require(entryAffordableAfterFee(
            entered: 10,
            balance: usd("10.00"),
            feeBps: 100,
            feeChargedOnTop: true
        ))

        #expect(corrected.formatted() == "$9.90")
        // The entry plus its own on-top fee stays inside the balance.
        #expect(corrected.value * Decimal(string: "1.01")! <= Decimal(10))
    }

    @Test("The whole balance drops to what a grossed-up fee leaves")
    func wholeBalance_feeGrossedUp() throws {
        let corrected = try #require(entryAffordableAfterFee(
            entered: 10,
            balance: usd("10.00"),
            feeBps: 100,
            feeChargedOnTop: false
        ))

        #expect(corrected.formatted() == "$9.90")
        #expect(corrected.grossingUpLaunchpadSellFee(bps: 100).value <= Decimal(10))
    }

    @Test("The correction is floored so the fee still fits when rounding would not")
    func correction_isFlooredNotRounded() throws {
        // $10.11 / 1.01 = $10.0099, which rounds up to $10.01 — and $10.01 plus
        // its own 1% fee is $10.1101, back over the balance. Flooring to $10.00
        // keeps the debit inside it.
        let corrected = try #require(entryAffordableAfterFee(
            entered: Decimal(string: "10.11")!,
            balance: usd("10.11"),
            feeBps: 100,
            feeChargedOnTop: true
        ))

        #expect(corrected.formatted() == "$10.00")
        #expect(corrected.value * Decimal(string: "1.01")! <= Decimal(string: "10.11")!)
    }

    @Test("Re-entering the corrected amount does not correct it again")
    func correction_isIdempotent() throws {
        let corrected = try #require(entryAffordableAfterFee(
            entered: 10,
            balance: usd("10.00"),
            feeBps: 100,
            feeChargedOnTop: true
        ))

        #expect(entryAffordableAfterFee(
            entered: corrected.value,
            balance: usd("10.00"),
            feeBps: 100,
            feeChargedOnTop: true
        ) == nil)
    }

    @Test("An entry beyond the balance is corrected down to the maximum too")
    func entryOverBalance_correctsToMaximum() throws {
        let corrected = try #require(entryAffordableAfterFee(
            entered: 50,
            balance: usd("10.00"),
            feeBps: 100,
            feeChargedOnTop: true
        ))

        #expect(corrected.formatted() == "$9.90")
    }

    @Test("The correction is denominated in the balance's currency")
    func correction_usesBalanceCurrency() throws {
        let corrected = try #require(entryAffordableAfterFee(
            entered: 1_000,
            balance: FiatAmount(value: 1_000, currency: .jpy),
            feeBps: 100,
            feeChargedOnTop: true
        ))

        // ¥ has no fractional unit, so the correction floors to whole yen.
        #expect(corrected.currency == .jpy)
        #expect(corrected.value == 990)
    }
}
