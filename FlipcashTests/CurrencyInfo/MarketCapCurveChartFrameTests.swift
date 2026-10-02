//
//  MarketCapCurveChartFrameTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("MarketCapCurveChart.Frame")
struct MarketCapCurveChartFrameTests {

    private static let quarksPerToken: UInt64 = 10_000_000_000

    private let explainer = MarketCapExplainer(
        todaySupplyQuarks: 1_250_000 * quarksPerToken,
        heldQuarks: 12_400 * quarksPerToken
    )!

    private func frame(at position: Double) -> MarketCapCurveChart.Frame {
        MarketCapCurveChart.Frame(explainer: explainer, position: position, reserveText: { "R\($0)" })
    }

    private static let positions: [Double] = [0, 0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9, 1]

    @Test("The frame selects the stop at the slider position and always carries Today")
    func selectionAndToday() {
        for position in Self.positions {
            let f = frame(at: position)
            #expect(f.selection == explainer.stop(atTrackPosition: position))
            #expect(f.today == explainer.todayStop)
            #expect(f.selectedX == f.selection.supply.doubleValue)
            #expect(f.selectedY == f.selection.price.doubleValue)
            #expect(f.todayX == explainer.todayStop.supply.doubleValue)
            #expect(f.todayY == explainer.todayStop.price.doubleValue)
        }
    }

    @Test("The domain covers the selection at every position")
    func domainCoversSelection() {
        for position in Self.positions {
            let f = frame(at: position)
            #expect(f.xDomain.contains(f.selectedX))
            #expect(f.yRange.contains(f.selectedY))
        }
    }

    @Test("Today is inside the domain when the selection is at or past it, and may fall outside when far below")
    func domainAndToday() {
        let atToday = frame(at: explainer.trackPosition(of: explainer.todayStop))
        #expect(atToday.xDomain.contains(atToday.todayX))
        #expect(atToday.yRange.contains(atToday.todayY))

        let top = frame(at: 1)
        #expect(top.xDomain.contains(top.todayX))

        // Far below Today, the right edge (selection + lookahead) is left of Today's supply.
        let bottom = frame(at: 0)
        #expect(!bottom.xDomain.contains(bottom.todayX))
    }

    @Test("The solid and faded halves of the curve meet at the selection")
    func solidAndFadedMeetAtSelection() {
        for position in Self.positions {
            let f = frame(at: position)
            let marker = MarketCapExplainer.CurvePoint(supply: f.selectedX, price: f.selectedY)
            #expect(f.solid.last == marker)
            #expect(f.faded.first == marker)
            #expect(f.solid.dropLast().allSatisfy { $0.supply < f.selectedX })
            #expect(f.faded.dropFirst().allSatisfy { $0.supply > f.selectedX })
        }
    }

    @Test("The sampled curve spans 0 to the chart's right edge, increasing in supply, at every position")
    func curveSpansToTheEdge() {
        for position in Self.positions {
            let f = frame(at: position)
            #expect(f.points.first?.supply == 0)
            #expect(f.points.last?.supply == Double(explainer.chartSupplyMax(for: f.selection)))
            #expect(zip(f.points, f.points.dropFirst()).allSatisfy { $0.supply < $1.supply })
        }
    }

    @Test("The sample count only grows as the selection moves right, and is never empty")
    func curvePointCountGrowsWithSelection() {
        // The right edge is selection + a fixed lookahead, so the window slides
        // right and the sample count tracks it; it never drops or collapses.
        let counts = Self.positions.map { frame(at: $0).points.count }
        #expect(counts.min()! > 0)
        #expect(counts == counts.sorted())
    }

    @Test("Solid plus faded is the sampled curve with the selection marker joined to both halves")
    func solidAndFadedCoverTheCurve() {
        for position in Self.positions {
            let f = frame(at: position)
            let others = f.points.filter { $0.supply != f.selectedX }.count
            #expect(f.solid.count + f.faded.count == others + 2)
        }
    }

    @Test("The selection label names Today only at Today")
    func selectionLabel() {
        let atToday = frame(at: explainer.trackPosition(of: explainer.todayStop))
        #expect(atToday.selectionLabel == "R\(explainer.todayStop.reserve) Today")

        let other = frame(at: 0.9)
        #expect(other.selectionLabel == "R\(other.selection.reserve)")
    }
}
