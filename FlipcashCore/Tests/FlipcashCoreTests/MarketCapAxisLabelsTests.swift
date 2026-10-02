//
//  MarketCapAxisLabelsTests.swift
//  FlipcashCoreTests
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("MarketCapAxisLabels")
struct MarketCapAxisLabelsTests {

    private typealias Item = MarketCapAxisLabels.Item

    private func item(_ id: Int, at position: Double, width: CGFloat? = 40, today: Bool = false) -> Item {
        Item(id: Foundation.Decimal(id), position: position, width: width, isToday: today)
    }

    private func id(_ value: Int) -> Foundation.Decimal { Foundation.Decimal(value) }

    @Test("Well-separated labels all draw, centered on their ticks")
    func separatedLabelsDraw() {
        let layout = MarketCapAxisLabels.layout(
            [item(1, at: 0.2), item(2, at: 0.5, today: true), item(3, at: 0.8)],
            trackWidth: 300
        )
        #expect(layout == [id(1): 60, id(2): 150, id(3): 240])
    }

    @Test("Labels are clamped to stay inside the track")
    func clampedInsideTrack() {
        let layout = MarketCapAxisLabels.layout(
            [item(1, at: 0, width: 50), item(2, at: 1, width: 50)],
            trackWidth: 300
        )
        #expect(layout[id(1)] == 25)
        #expect(layout[id(2)] == 275)
    }

    @Test("A label wider than the track is centered at half its width, never negative")
    func widerThanTrack() {
        let layout = MarketCapAxisLabels.layout([item(1, at: 0.5, width: 80)], trackWidth: 60)
        #expect(layout[id(1)] == 40)
    }

    @Test("Today always draws, and a fixed label colliding with it is the one dropped")
    func todayWinsCollision() {
        // Fixed label listed first, so only the Today-first ordering can save Today.
        let layout = MarketCapAxisLabels.layout(
            [item(1, at: 0.5), item(2, at: 0.52, today: true)],
            trackWidth: 300
        )
        #expect(layout[id(2)] != nil)
        #expect(layout[id(1)] == nil)
    }

    @Test("A fixed label within the gap of a drawn one is dropped; exactly the gap away is kept")
    func gapBoundary() {
        // Two 40pt labels: centers must be at least 40 + 6 = 46pt apart.
        let tooClose = MarketCapAxisLabels.layout(
            [item(1, at: 0.5, today: true), item(2, at: (150 + 45.9) / 300)],
            trackWidth: 300
        )
        #expect(tooClose[id(2)] == nil)

        let farEnough = MarketCapAxisLabels.layout(
            [item(1, at: 0.5, today: true), item(2, at: (150 + 46) / 300)],
            trackWidth: 300
        )
        #expect(farEnough[id(2)] != nil)
    }

    @Test("A dropped label does not block the next one it clears")
    func droppedLabelDoesNotBlock() {
        let layout = MarketCapAxisLabels.layout(
            [item(1, at: 0.5, today: true), item(2, at: 0.55), item(3, at: 0.8)],
            trackWidth: 300
        )
        #expect(layout[id(2)] == nil)
        #expect(layout[id(3)] == 240)
    }

    @Test("Labels not yet measured are skipped")
    func unmeasuredSkipped() {
        let layout = MarketCapAxisLabels.layout(
            [item(1, at: 0.2, width: nil), item(2, at: 0.8)],
            trackWidth: 300
        )
        #expect(layout[id(1)] == nil)
        #expect(layout[id(2)] == 240)
    }

    @Test("Today is drawn even when the track is too narrow for any other label")
    func todayAlwaysDrawn() {
        let layout = MarketCapAxisLabels.layout(
            [item(1, at: 0.0), item(2, at: 0.1, today: true), item(3, at: 0.2)],
            trackWidth: 100
        )
        #expect(layout[id(2)] != nil)
    }
}
