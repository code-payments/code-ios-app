//
//  CollectionPaymentSheetContentTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// What the pay sheet and Payment Details draw, from the inputs of the `collection_funding.json`
/// cases for sections 5, 6 and 9. The fixture lives in the FlipcashCoreVectors package, which
/// this target can't load, so the inputs are copied here.
@Suite("Collection pay sheet and Payment Details")
struct CollectionPaymentSheetContentTests {

    private typealias Line = CollectionPaymentSheetContent.Line

    private static let dollars = "dollars"

    private static func content(
        amountMicros: Int64 = 10_000_000,
        selected: String? = nil,
        balances: [(id: String, name: String, fiatMicros: Int64, feeBps: Int64)]
    ) throws -> CollectionPaymentSheetContent {
        let plan = try planCollectionFunding(
            amountMicros: amountMicros,
            minorDigits: 2,
            minimumTopUpMicros: 5_000_000,
            selected: selected,
            lastPaid: nil,
            dollars: dollars,
            balances: balances.map { CollectionFundingBalance(id: $0.id, fiatMicros: $0.fiatMicros, sellFeeBps: $0.feeBps) }
        )
        let display = CollectionFundingDisplay(
            plan: plan,
            currency: .usd,
            dollars: dollars,
            names: Dictionary(uniqueKeysWithValues: balances.map { ($0.id, $0.name) })
        )
        return CollectionPaymentSheetContent(plan: plan, display: display)
    }

    /// $8.00 Dollars and $6.00 Jeffy (`s5-s6-convert-shortfall`, `s6-pay-in-jeffy`).
    private static let dollarsAndJeffy: [(id: String, name: String, fiatMicros: Int64, feeBps: Int64)] = [
        (dollars, "Dollars", 8_000_000, 0),
        ("jeffy", "Jeffy", 6_000_000, 100),
    ]

    @Test("5.2 and 5.3: Dollars pays, Jeffy sells into it with its fee")
    func section5() throws {
        let content = try Self.content(balances: Self.dollarsAndJeffy)

        #expect(content.feeLine == "plus ~$0.02 of conversion fees")
        #expect(content.payingCurrency == Self.dollars)
        #expect(content.pay == Line(currency: Self.dollars, name: "Dollars", amount: "$10.00", sublabels: []))
        #expect(content.use == [
            Line(currency: Self.dollars, name: "Dollars", amount: "$8.00", sublabels: []),
            Line(currency: "jeffy", name: "Jeffy", amount: "$2.02", sublabels: ["~$0.02 conversion fee"]),
        ])
        #expect(content.total == .init(label: "Total", amount: "$10.02"))
    }

    @Test("6.4 and 6.5: Jeffy picked, Dollars buy the rest at no fee")
    func section6() throws {
        let content = try Self.content(selected: "jeffy", balances: Self.dollarsAndJeffy)

        #expect(content.feeLine == "no conversion fees")
        #expect(content.payingCurrency == "jeffy")
        #expect(content.pay == Line(currency: "jeffy", name: "Jeffy", amount: "$10.00", sublabels: []))
        #expect(content.use == [
            Line(currency: "jeffy", name: "Jeffy", amount: "$6.00", sublabels: []),
            Line(currency: Self.dollars, name: "Dollars", amount: "$4.00", sublabels: []),
        ])
        #expect(content.total == .init(label: "Total", amount: "$10.00"))
    }

    @Test("9.2 and 9.3: 29 small balances, drawn largest first with their fee lines")
    func section9() throws {
        let fiat: [Int64] = [
            1_000_000, 610_000, 580_000, 560_000, 540_000, 520_000, 500_000, 480_000, 460_000, 440_000,
            420_000, 400_000, 380_000, 360_000, 340_000, 320_000, 300_000, 280_000, 260_000, 240_000,
            220_000, 200_000, 180_000, 160_000, 140_000, 130_000, 110_000, 90_000, 70_000,
        ]
        let balances = [(Self.dollars, "Dollars", Int64(0), Int64(0))] + fiat.enumerated().map { index, micros in
            (String(format: "jeffy-%02d", index + 1), "Jeffy \(index + 1)", micros, Int64(100))
        }
        let content = try Self.content(balances: balances)

        #expect(content.feeLine == "plus ~$0.10 of conversion fees")
        #expect(content.pay == Line(currency: Self.dollars, name: "Dollars", amount: "$10.00", sublabels: []))
        #expect(content.use.count == 29)
        #expect(content.use.map(\.name) == (1...29).map { "Jeffy \($0)" })
        #expect(content.use.map(\.amount) == [
            "$0.81", "$0.61", "$0.58", "$0.56", "$0.54", "$0.52", "$0.50", "$0.48", "$0.46", "$0.44",
            "$0.42", "$0.40", "$0.38", "$0.36", "$0.34", "$0.32", "$0.30", "$0.28", "$0.26", "$0.24",
            "$0.22", "$0.20", "$0.18", "$0.16", "$0.14", "$0.13", "$0.11", "$0.09", "$0.07",
        ])
        #expect(content.use.prefix(7).allSatisfy { $0.sublabels == ["~$0.01 conversion fee"] })
        #expect(content.use.dropFirst(7).allSatisfy { $0.sublabels == ["<$0.01 conversion fee"] })
        #expect(content.use.map(\.currency) == (1...29).map { String(format: "jeffy-%02d", $0) })
        // The spec's label; 9.3 draws "Total Used" "~$10.10", an open question with design.
        #expect(content.total == .init(label: "Total", amount: "$10.10"))
    }

    @Test("Nothing converting draws no fee line, so no Payment Details")
    func noConversion() throws {
        let content = try Self.content(balances: [(Self.dollars, "Dollars", 12_000_000, 0)])

        #expect(content.feeLine == nil)
    }

    @Test("A shortfall conversions can't cover draws no fee line; the short state shows instead")
    func uncoverable() throws {
        let content = try Self.content(balances: [
            (Self.dollars, "Dollars", 3_000_000, 0),
            ("jeffy", "Jeffy", 2_000_000, 100),
        ])

        #expect(content.feeLine == nil)
    }
}
