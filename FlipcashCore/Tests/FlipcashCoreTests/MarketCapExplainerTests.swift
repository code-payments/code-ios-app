//
//  MarketCapExplainerTests.swift
//  FlipcashCoreTests
//

import Testing
import Foundation
@testable import FlipcashCore
@preconcurrency import BigDecimal

@Suite("MarketCapExplainer")
struct MarketCapExplainerTests {

    static let quarksPerToken: UInt64 = 10_000_000_000

    /// 1.25M tokens in circulation, 12,400 held.
    let explainer = MarketCapExplainer(
        todaySupplyQuarks: 1_250_000 * quarksPerToken,
        heldQuarks: 12_400 * quarksPerToken
    )!

    private func stop(reserve: Foundation.Decimal) -> MarketCapExplainer.Stop {
        explainer.stops.first { $0.reserve == reserve }!
    }

    private func rounded(_ value: Foundation.Decimal, _ places: Int) -> Foundation.Decimal {
        value.rounded(to: places)
    }

    // MARK: - Acceptance vectors

    @Test("Today: price $0.02994, worth $369.18, reserve about $22.7K")
    func today() throws {
        let today = explainer.todayStop
        #expect(today.isToday)
        #expect(rounded(today.price, 5) == Foundation.Decimal(string: "0.02994")!)
        #expect(rounded(try #require(explainer.worth(at: today)), 2) == Foundation.Decimal(string: "369.18")!)
        #expect(rounded(today.reserve, -2) == 22_700)
    }

    @Test("Fixed stops: reserve to price to worth of 12,400 tokens", arguments: [
        (Foundation.Decimal(5_000), "0.0144", Foundation.Decimal(177)),
        (Foundation.Decimal(100_000), "0.0977", Foundation.Decimal(1_205)),
        (Foundation.Decimal(1_000_000), "0.887", Foundation.Decimal(10_941)),
        (Foundation.Decimal(10_000_000), "8.78", Foundation.Decimal(108_304)),
    ])
    func fixedStops(reserve: Foundation.Decimal, price: String, worth: Foundation.Decimal) throws {
        let stop = stop(reserve: reserve)
        #expect(!stop.isToday)
        let places = price.split(separator: ".")[1].count
        #expect(rounded(stop.price, places) == Foundation.Decimal(string: price)!)
        #expect(rounded(try #require(explainer.worth(at: stop)), 0) == worth)
    }

    // MARK: - Axis

    @Test("Ticks are the four fixed reserves plus Today, sorted")
    func ticks() {
        let reserves = explainer.stops.map(\.reserve)
        #expect(reserves == reserves.sorted())
        #expect(reserves.count == 5)
        #expect(explainer.stops.filter(\.isToday).count == 1)
    }

    @Test("Track runs min($5K, Today) to max($10M, Today), log-spaced")
    func track() {
        #expect(explainer.trackPosition(of: stop(reserve: 5_000)) == 0)
        #expect(explainer.trackPosition(of: stop(reserve: 10_000_000)) == 1)
        let today = explainer.trackPosition(of: explainer.todayStop)
        #expect(today > 0 && today < 1)
    }

    @Test("A Today above $10M gets a higher stop to its right")
    func todayBeyondFixedRange() {
        let big = MarketCapExplainer(todaySupplyQuarks: 8_000_000 * Self.quarksPerToken, heldQuarks: nil)!
        #expect(big.todayStop.reserve > 10_000_000)
        #expect(big.stops.last?.isToday == false)
        #expect(big.trackPosition(of: big.todayStop) < 1)
    }

    @Test("Dragging near Today reads as Today; elsewhere it does not")
    func dragSnapsToTodayOnly() {
        let todayPosition = explainer.trackPosition(of: explainer.todayStop)
        #expect(explainer.stop(atTrackPosition: todayPosition + 0.001).isToday)
        let away = explainer.stop(atTrackPosition: 0.9)
        #expect(!away.isToday)
        #expect(away.reserve > explainer.todayStop.reserve)
        #expect(explainer.stop(atTrackPosition: 0).reserve == 5_000)
        #expect(explainer.stop(atTrackPosition: 1).reserve == 10_000_000)
    }

    @Test("A mid-track position yields a supply and price strictly between its neighbours")
    func continuousSelection() {
        let low = explainer.stop(atTrackPosition: 0.6)
        let high = explainer.stop(atTrackPosition: 0.8)
        #expect(low.supply < high.supply)
        #expect(low.price <= high.price)
    }

    // MARK: - Chart

    @Test("Chart spans 0 to selected supply + 750K tokens, $0.01 to the price at the edge")
    func chartDomain() {
        let today = explainer.todayStop
        #expect(explainer.chartSupplyMax(for: today) == 2_000_000)
        let points = explainer.curvePoints(for: today)
        #expect(points.first?.supply == 0)
        #expect(points.last?.supply == 2_000_000)
        let range = explainer.chartPriceRange(for: today)
        #expect(range.lowerBound == 0.01)
        #expect(range.upperBound == points.last?.price)
    }

    @Test("The selected supply stays inside the chart's x domain at every slider position",
          arguments: [10_000, 1_250_000, 12_000_000, 20_900_000, 21_000_000] as [UInt64])
    func selectionStaysInChart(todayTokens: UInt64) throws {
        let e = try #require(MarketCapExplainer(todaySupplyQuarks: todayTokens * Self.quarksPerToken, heldQuarks: nil))
        for i in 0...100 {
            let stop = e.stop(atTrackPosition: Double(i) / 100)
            let domain = e.chartXDomain(for: stop)
            let fraction = stop.supply.doubleValue / domain.upperBound
            #expect(domain.lowerBound == 0)
            #expect(fraction <= 1 - MarketCapExplainer.chartEdgeMargin + 1e-9)
        }
    }

    // MARK: - Extended stops

    private func explainer(reserve: Int) throws -> MarketCapExplainer {
        let supply = DiscreteBondingCurve().preciseSupplyFromValue(BigDecimal(reserve)).asDecimal()
        let quarks = UInt64(NSDecimalNumber(decimal: (supply * Foundation.Decimal(Self.quarksPerToken)).rounded(to: 0)).doubleValue)
        return try #require(MarketCapExplainer(todaySupplyQuarks: quarks, heldQuarks: nil))
    }

    @Test("Stops extend ×10 while the top stop is within 2× Today's reserve", arguments: [
        (22_700, [5_000, 100_000, 1_000_000, 10_000_000]),
        (171_000, [5_000, 100_000, 1_000_000, 10_000_000]),
        (6_000_000, [5_000, 100_000, 1_000_000, 10_000_000, 100_000_000]),
        (10_000_000, [5_000, 100_000, 1_000_000, 10_000_000, 100_000_000]),
        (60_000_000, [5_000, 100_000, 1_000_000, 10_000_000, 100_000_000, 1_000_000_000]),
    ] as [(Int, [Int])])
    func extendedStops(reserve: Int, fixed: [Int]) throws {
        let e = try explainer(reserve: reserve)
        let expected = Set(fixed.map { Foundation.Decimal($0) })
        let fixedStops = e.stops.filter { !$0.isToday }
        #expect(Set(fixedStops.map(\.reserve)).isSubset(of: expected))
        // Today replaces a fixed stop only when it lands on it.
        #expect(expected.count - fixedStops.count <= 1)
        #expect(e.stops.last?.reserve == Foundation.Decimal(fixed.last!))
        let hasToday = e.stops.contains { $0.isToday }
        #expect(hasToday)
        #expect(e.trackPosition(of: e.todayStop) < 1)
        let reserves = e.stops.map(\.reserve)
        #expect(reserves == reserves.sorted())
    }

    @Test("Stops never pass the reserve at max supply")
    func stopsAreCapped() {
        let reserves = MarketCapExplainer.stopReserves(
            todayReserve: 900_000_000_000,
            maxReserve: 1_139_973_004_315
        )
        #expect(reserves.last == 1_000_000_000_000)
        let capped = MarketCapExplainer.stopReserves(todayReserve: 900_000_000_000, maxReserve: 500_000_000_000)
        #expect(capped.allSatisfy { $0 <= 500_000_000_000 })
    }

    @Test("At $60M the selection stays inside the chart at every slider position")
    func selectionInChartAtSixtyMillion() throws {
        let e = try explainer(reserve: 60_000_000)
        for i in 0...100 {
            let stop = e.stop(atTrackPosition: Double(i) / 100)
            let domain = e.chartXDomain(for: stop)
            #expect(stop.supply.doubleValue / domain.upperBound <= 1 - MarketCapExplainer.chartEdgeMargin + 1e-9)
        }
    }

    // MARK: - Ownership

    @Test("Ownership rows from held quarks")
    func ownership() {
        let ownership = explainer.ownership
        #expect(ownership.tokens == 12_400)
        #expect(ownership.shareOfCirculating == Foundation.Decimal(12_400) / 1_250_000)
        #expect(ownership.shareOfMax == Foundation.Decimal(12_400) / 21_000_000)
    }

    @Test("Without holdings the dependent values are nil and nothing is worth anything")
    func noHoldings() {
        let none = MarketCapExplainer(todaySupplyQuarks: 1_250_000 * Self.quarksPerToken, heldQuarks: nil)!
        #expect(none.ownership.tokens == nil)
        #expect(none.ownership.shareOfCirculating == nil)
        #expect(none.worth(at: none.todayStop) == nil)
    }
}
