//
//  CollectionFundingPlanValidationTests.swift
//  FlipcashCoreTests
//

import Testing
@testable import FlipcashCore

@Suite("Collection funding plan validation")
struct CollectionFundingPlanValidationTests {

    private static let dollars = "dollars"

    private static func plan(
        amountMicros: Int64 = 10_000_000,
        minorDigits: Int = 2,
        minimumTopUpMicros: Int64 = 0,
        balances: [CollectionFundingBalance]
    ) throws(CollectionFundingPlanError) -> CollectionFundingPlan {
        try planCollectionFunding(
            amountMicros: amountMicros,
            minorDigits: minorDigits,
            minimumTopUpMicros: minimumTopUpMicros,
            selected: nil,
            lastPaid: nil,
            dollars: dollars,
            balances: balances
        )
    }

    @Test("A negative amount is rejected")
    func negativeAmount() {
        #expect(throws: CollectionFundingPlanError.negativeAmount(-1)) {
            try Self.plan(amountMicros: -1, balances: [])
        }
    }

    @Test("Minor digits outside 0...6 are rejected", arguments: [-1, 7])
    func invalidMinorDigits(_ digits: Int) {
        #expect(throws: CollectionFundingPlanError.invalidMinorDigits(digits)) {
            try Self.plan(minorDigits: digits, balances: [])
        }
    }

    @Test("Minor digits 0 and 6 are accepted", arguments: [0, 6])
    func boundaryMinorDigits(_ digits: Int) throws {
        let plan = try Self.plan(minorDigits: digits, balances: [
            CollectionFundingBalance(id: Self.dollars, fiatMicros: 10_000_000, sellFeeBps: 0),
        ])
        #expect(plan.payableWithoutTopUp)
    }

    @Test("A negative top-up minimum is rejected")
    func negativeMinimumTopUp() {
        #expect(throws: CollectionFundingPlanError.negativeMinimumTopUp(-5)) {
            try Self.plan(minimumTopUpMicros: -5, balances: [])
        }
    }

    @Test("A negative balance is rejected")
    func negativeBalance() {
        #expect(throws: CollectionFundingPlanError.negativeBalance(id: "jeffy", micros: -1)) {
            try Self.plan(balances: [
                CollectionFundingBalance(id: Self.dollars, fiatMicros: 10_000_000, sellFeeBps: 0),
                CollectionFundingBalance(id: "jeffy", fiatMicros: -1, sellFeeBps: 100),
            ])
        }
    }

    /// Before validation, a second Dollars entry counted toward capacity while only the first one
    /// funded a leg: $5 + $5 read as enough for $10, and the plan paid with $5.
    @Test("A repeated Dollars id is rejected instead of under-funding")
    func duplicateDollars() {
        #expect(throws: CollectionFundingPlanError.duplicateBalance(id: Self.dollars)) {
            try Self.plan(balances: [
                CollectionFundingBalance(id: Self.dollars, fiatMicros: 5_000_000, sellFeeBps: 0),
                CollectionFundingBalance(id: Self.dollars, fiatMicros: 5_000_000, sellFeeBps: 0),
            ])
        }
    }

    @Test("A repeated paying-currency id is rejected")
    func duplicatePaying() {
        #expect(throws: CollectionFundingPlanError.duplicateBalance(id: "jeffy")) {
            try planCollectionFunding(
                amountMicros: 10_000_000,
                minorDigits: 2,
                minimumTopUpMicros: 0,
                selected: "jeffy",
                lastPaid: nil,
                dollars: Self.dollars,
                balances: [
                    CollectionFundingBalance(id: "jeffy", fiatMicros: 6_000_000, sellFeeBps: 100),
                    CollectionFundingBalance(id: "jeffy", fiatMicros: 6_000_000, sellFeeBps: 100),
                ]
            )
        }
    }

    @Test("Zero amounts and zero balances are accepted")
    func zeroes() throws {
        let plan = try Self.plan(amountMicros: 0, balances: [
            CollectionFundingBalance(id: Self.dollars, fiatMicros: 0, sellFeeBps: 0),
        ])
        #expect(plan.payableWithoutTopUp)
        #expect(plan.legs.allSatisfy { $0.soldMicros == 0 })
    }

    /// A balance worth less than half a cent displays as $0.00, so the planner drops it before
    /// anything else: no leg, and the next balance covers what it would have.
    @Test("A balance under half a minor unit is dust and gets no leg")
    func dustGetsNoLeg() throws {
        let plan = try Self.plan(balances: [
            CollectionFundingBalance(id: Self.dollars, fiatMicros: 5_000_000, sellFeeBps: 0),
            CollectionFundingBalance(id: "dust", fiatMicros: 4_999, sellFeeBps: 100),
            CollectionFundingBalance(id: "jeffy", fiatMicros: 6_000_000, sellFeeBps: 100),
        ])
        #expect(plan.legs.map(\.source) == [Self.dollars, "jeffy"])
        #expect(plan.payableWithoutTopUp)
    }

    @Test("Exactly half a minor unit is not dust and funds")
    func halfUnitFunds() throws {
        let plan = try Self.plan(balances: [
            CollectionFundingBalance(id: Self.dollars, fiatMicros: 5_000_000, sellFeeBps: 0),
            CollectionFundingBalance(id: "crumb", fiatMicros: 5_000, sellFeeBps: 100),
            CollectionFundingBalance(id: "jeffy", fiatMicros: 6_000_000, sellFeeBps: 100),
        ])
        #expect(plan.legs.filter(\.conversion).map(\.source) == ["crumb", "jeffy"])
        #expect(plan.legs.first { $0.source == "crumb" }?.soldMicros == 5_000)
    }

    /// Dust Dollars count as zero, so the top-up's split has nothing from the balance.
    @Test("Dust Dollars count as zero in the top-up split")
    func dustDollarsCountAsZero() throws {
        let plan = try Self.plan(amountMicros: 2_000_000, minimumTopUpMicros: 5_000_000, balances: [
            CollectionFundingBalance(id: Self.dollars, fiatMicros: 4_000, sellFeeBps: 0),
        ])
        #expect(plan.shortfallMicros == 2_000_000)
        #expect(plan.topUpMicros == 5_000_000)
        #expect(plan.legs.first?.dollarsSplit == .init(fromBalanceMicros: 0, fromTopUpMicros: 2_000_000))
    }

    /// The floor follows the currency's minor unit: half of 1 in a zero-digit currency is 500,000
    /// micros.
    @Test("The dust floor is half the request currency's minor unit", arguments: [(0, Int64(500_000)), (2, 5_000), (6, 1)])
    func dustFloorFollowsMinorDigits(_ digits: Int, _ floor: Int64) {
        let unit = microsPerMinorUnit(minorDigits: digits)
        #expect(isDust(floor - 1, minorUnitMicros: unit))
        #expect(!isDust(floor, minorUnitMicros: unit))
    }
}
