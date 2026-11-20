//
//  CollectionPaymentSheetContentTests.swift
//  FlipcashTests
//

import Foundation
import SwiftUI
import Testing
import UIKit
import FlipcashCore
@testable import Flipcash

/// What the pay sheet and Payment Details draw, from the inputs of the `collection_funding.json`
/// cases for sections 1, 2, 4, 5, 6, 7, 8 and 9. The fixture lives in the FlipcashCoreVectors package, which
/// this target can't load, so the inputs are copied here.
@Suite("Collection pay sheet and Payment Details")
struct CollectionPaymentSheetContentTests {

    private typealias Line = CollectionPaymentSheetContent.Line

    private static let dollars = "dollars"

    private static func content(
        amountMicros: Int64 = 10_000_000,
        selected: String? = nil,
        lastPaid: String? = nil,
        balances: [(id: String, name: String, fiatMicros: Int64, feeBps: Int64)]
    ) throws -> CollectionPaymentSheetContent {
        let (plan, display) = try inputs(amountMicros: amountMicros, selected: selected, lastPaid: lastPaid, balances: balances)
        return CollectionPaymentSheetContent(plan: plan, display: display, currency: .usd)
    }

    private static func inputs(
        amountMicros: Int64,
        selected: String? = nil,
        lastPaid: String?,
        balances: [(id: String, name: String, fiatMicros: Int64, feeBps: Int64)]
    ) throws -> (CollectionFundingPlan, CollectionFundingDisplay) {
        let plan = try planCollectionFunding(
            amountMicros: amountMicros,
            minorDigits: 2,
            minimumTopUpMicros: 5_000_000,
            selected: selected,
            lastPaid: lastPaid,
            dollars: dollars,
            balances: balances.map { CollectionFundingBalance(id: $0.id, fiatMicros: $0.fiatMicros, sellFeeBps: $0.feeBps) }
        )
        let display = CollectionFundingDisplay(
            plan: plan,
            currency: .usd,
            dollars: dollars,
            names: Dictionary(uniqueKeysWithValues: balances.map { ($0.id, $0.name) })
        )
        return (plan, display)
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
        #expect(content.detailsEntries == [.feeLine])
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
        #expect(content.detailsEntries.isEmpty)
    }

    @Test("A payment the balances cover draws no short state")
    func coveredHasNoTopUp() throws {
        #expect(try Self.content(balances: Self.dollarsAndJeffy).topUp == nil)
    }

    // MARK: - Top-up (S5)

    private static let footnote = "The minimum you can add with Apple Pay is $5."

    @Test("1.1: no balance adds the whole amount")
    func section1() throws {
        let content = try Self.content(balances: [])

        #expect(content.topUp == .init(
            micros: 10_000_000, shortBy: "You’re $10.00 Short", button: "Add $10.00 and Pay $10.00", footnote: Self.footnote
        ))
        #expect(content.feeLine == nil)
        #expect(content.use == [
            Line(currency: Self.dollars, name: "Dollars", amount: "$10.00", sublabels: ["$10.00 from Apple Pay"]),
        ])
    }

    @Test("2.1: a $2 request at a $0 balance adds the $5 minimum")
    func section2() throws {
        let content = try Self.content(amountMicros: 2_000_000, balances: [(Self.dollars, "Dollars", 0, 0)])

        #expect(content.topUp == .init(
            micros: 5_000_000, shortBy: "You’re $2.00 Short", button: "Add $5.00 and Pay $2.00", footnote: Self.footnote
        ))
        #expect(content.feeLine == nil)
        // Only the $2 this payment uses shows; the other $3 stays in the balance.
        #expect(content.use == [
            Line(currency: Self.dollars, name: "Dollars", amount: "$2.00", sublabels: ["$2.00 from Apple Pay"]),
        ])
    }

    @Test("4.2: $6 Dollars toward $10 adds the $5 minimum, no fee line")
    func section4() throws {
        let content = try Self.content(balances: [(Self.dollars, "Dollars", 6_000_000, 0)])

        #expect(content.topUp == .init(
            micros: 5_000_000, shortBy: "You’re $4.00 Short", button: "Add $5.00 and Pay $10.00", footnote: Self.footnote
        ))
        #expect(content.feeLine == nil)
    }

    @Test("7.2 and 7.3: the top-up removes the Jeffy conversion; Payment Details shows the plan after it")
    func section7() throws {
        let content = try Self.content(amountMicros: 11_000_000, balances: [
            (Self.dollars, "Dollars", 6_000_000, 0),
            ("jeffy", "Jeffy", 2_990_000, 100),
        ])

        #expect(content.topUp == .init(
            micros: 5_000_000, shortBy: "You’re $2.04 Short", button: "Add $5.00 and Pay $11.00", footnote: Self.footnote
        ))
        #expect(content.feeLine == nil)
        #expect(content.payingCurrency == Self.dollars)
        #expect(content.pay == Line(currency: Self.dollars, name: "Dollars", amount: "$11.00", sublabels: []))
        #expect(content.use == [
            Line(currency: Self.dollars, name: "Dollars", amount: "$11.00", sublabels: ["$6.00 from balance", "$5.00 from Apple Pay"]),
        ])
        #expect(content.total == .init(label: "Total", amount: "$11.00"))
    }

    @Test("7.2 to 7.3: with no fee line, the short line is what opens Payment Details, and it opens on 7.3")
    func shortLineOpensDetails() throws {
        let content = try Self.content(amountMicros: 11_000_000, balances: [
            (Self.dollars, "Dollars", 6_000_000, 0),
            ("jeffy", "Jeffy", 2_990_000, 100),
        ])

        #expect(content.detailsEntries == [.shortLine])
        #expect(content.topUp?.shortBy == "You’re $2.04 Short")
        // 7.3: one Dollars row split between the balance and Apple Pay, then the total.
        #expect(CollectionPaymentSheetContent.title == "Payment Details")
        #expect(content.pay == Line(currency: Self.dollars, name: "Dollars", amount: "$11.00", sublabels: []))
        #expect(content.use == [
            Line(currency: Self.dollars, name: "Dollars", amount: "$11.00", sublabels: ["$6.00 from balance", "$5.00 from Apple Pay"]),
        ])
        #expect(content.total == .init(label: "Total", amount: "$11.00"))
    }

    @Test("8.2: an exact-cents top-up above the minimum, with the fee line from the plan after it")
    func section8() throws {
        let content = try Self.content(amountMicros: 21_000_000, lastPaid: "jeffy", balances: [
            ("jeffy", "Jeffy", 3_000_000, 100),
            (Self.dollars, "Dollars", 2_010_000, 0),
            ("other", "Other", 3_990_000, 100),
        ])

        #expect(content.topUp == .init(
            micros: 12_040_000, shortBy: "You’re $12.04 Short", button: "Add $12.04 and Pay $21.00", footnote: Self.footnote
        ))
        #expect(content.feeLine == "plus ~$0.04 of conversion fees")
        // Both lines end in ⓘ and open the same Payment Details.
        #expect(content.detailsEntries == [.feeLine, .shortLine])
        #expect(content.pay == Line(currency: "jeffy", name: "Jeffy", amount: "$21.00", sublabels: []))
        #expect(content.use == [
            Line(currency: "jeffy", name: "Jeffy", amount: "$3.00", sublabels: []),
            Line(currency: Self.dollars, name: "Dollars", amount: "$14.05", sublabels: ["$2.01 from balance", "$12.04 from Apple Pay"]),
            Line(currency: "other", name: "Other", amount: "$3.99", sublabels: ["~$0.04 conversion fee"]),
        ])
        #expect(content.total == .init(label: "Total", amount: "$21.04"))
    }

    /// Sections 1, 2, 4, 7 and 8 as (amount, last paid, balances).
    private static let topUpSections: [(amount: Int64, lastPaid: String?, balances: [(id: String, name: String, fiatMicros: Int64, feeBps: Int64)])] = [
        (10_000_000, nil, []),
        (2_000_000, nil, [(dollars, "Dollars", 0, 0)]),
        (10_000_000, nil, [(dollars, "Dollars", 6_000_000, 0)]),
        (11_000_000, nil, [(dollars, "Dollars", 6_000_000, 0), ("jeffy", "Jeffy", 2_990_000, 100)]),
        (21_000_000, "jeffy", [("jeffy", "Jeffy", 3_000_000, 100), (dollars, "Dollars", 2_010_000, 0), ("other", "Other", 3_990_000, 100)]),
    ]

    @Test("The sheet's localized short line and button read as the core display the vectors pin", arguments: 0..<5)
    func topUpStringsMatchCore(section: Int) throws {
        let c = Self.topUpSections[section]
        let (plan, display) = try Self.inputs(amountMicros: c.amount, lastPaid: c.lastPaid, balances: c.balances)
        let topUp = try #require(CollectionPaymentSheetContent(plan: plan, display: display, currency: .usd).topUp)

        #expect(topUp.shortBy == display.shortBy)
        #expect(topUp.button == display.addButton)
    }

    // MARK: - Payment Details inside the pay sheet

    @Test("5.3 and 7.3: the fee or short line's ⓘ pushes Payment Details, and back returns to the pay content")
    func detailsPushAndBack() throws {
        let feeLine = try Self.content(balances: Self.dollarsAndJeffy)
        let shortLine = try Self.content(amountMicros: 11_000_000, balances: [
            (Self.dollars, "Dollars", 6_000_000, 0),
            ("jeffy", "Jeffy", 2_990_000, 100),
        ])
        try #require(feeLine.detailsEntries == [.feeLine])
        try #require(shortLine.detailsEntries == [.shortLine])

        for content in [feeLine, shortLine] {
            let open = CollectionPaySheetPage(wantsDetails: true, isFinishing: false, content: content)
            let back = CollectionPaySheetPage(wantsDetails: false, isFinishing: false, content: content)
            #expect(open == .details)
            #expect(open.pagerProgress == 1)
            #expect(back == .pay)
            #expect(back.pagerProgress == 0)
        }
    }

    @Test("Payment Details stay shut with no line to open them from")
    func noLineNoDetails() throws {
        let noConversion = try Self.content(balances: [(Self.dollars, "Dollars", 12_000_000, 0)])
        try #require(noConversion.detailsEntries.isEmpty)

        #expect(CollectionPaySheetPage(wantsDetails: true, isFinishing: false, content: noConversion) == .pay)
        #expect(CollectionPaySheetPage(wantsDetails: true, isFinishing: false, content: nil) == .pay)
    }

    @Test("A running payment shows Finishing Payment over either page", arguments: [true, false])
    func finishingWins(wantsDetails: Bool) throws {
        let content = try Self.content(balances: Self.dollarsAndJeffy)

        #expect(CollectionPaySheetPage(wantsDetails: wantsDetails, isFinishing: true, content: content) == .finishing)
    }

    @Test("Mid-slide the sheet's height moves between the two pages' heights", arguments: [
        (CGFloat(0), CGFloat(200)), (0.25, 275), (0.5, 350), (1, 500), (-0.5, 200), (1.5, 500),
    ])
    func pagerHeight(progress: CGFloat, height: CGFloat) {
        #expect(CollectionPaySheetPager.height(of: [200, 500], at: progress) == height)
    }

    @Test("The pager measures the page it stands on, not the taller of the two", arguments: [
        (CGFloat(0), CGFloat(200)), (0.5, 350), (1, 500),
    ])
    @MainActor
    func pagerMeasuresShownPage(progress: CGFloat, height: CGFloat) {
        let pager = CollectionPaySheetPager(progress: progress) {
            Color.clear.frame(height: 200)
            Color.clear.frame(height: 500)
        }
        let size = UIHostingController(rootView: pager)
            .sizeThatFits(in: CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude))

        #expect(size.width == 390)
        #expect(size.height == height)
    }
}
