//
//  ReactionRowLayoutTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
@testable import FlipcashUI

/// The pill row's geometry: wrap onto at most two lines, collapse the rest into a "N more" pill that
/// keeps the "+" after it, and lift the cap once expanded.
@MainActor
@Suite("Reaction row layout")
struct ReactionRowLayoutTests {

    private static let pill = CGSize(width: 50, height: 28)
    private static let add = CGSize(width: 28, height: 28)
    private static let overflow: (Int) -> CGSize = { _ in CGSize(width: 36, height: 28) }
    private static let gap = ReactionRowLayout.spacing
    /// Two 28pt lines and the gap between them.
    private static let twoLines = 28 + gap + 28

    private func layout(pills: Int, add: CGSize? = Self.add, width: CGFloat = 200, maxLines: Int? = 2, trailing: Bool = false) -> ReactionRowLayout {
        ReactionRowLayout.make(
            pillSizes: Array(repeating: Self.pill, count: pills),
            addSize: add,
            overflowSize: Self.overflow,
            width: width,
            maxLines: maxLines,
            trailing: trailing
        )
    }

    @Test("Pills that fit on one line show them all, with the + last")
    func fitsOnOneLine() {
        let result = layout(pills: 2)
        #expect(result.hiddenCount == 0)
        #expect(result.overflowFrame == nil)
        #expect(result.pillFrames.count == 2)
        #expect(result.addFrame == CGRect(x: 2 * (50 + Self.gap), y: 0, width: 28, height: 28))
        #expect(result.height == 28)
    }

    @Test("Pills wrap onto a second line")
    func wrapsToSecondLine() {
        // A 200pt line holds three 50pt pills; the fourth starts line two.
        let result = layout(pills: 4)
        #expect(result.hiddenCount == 0)
        #expect(result.pillFrames[3].minY == 28 + Self.gap)
        #expect(result.height == Self.twoLines)
    }

    @Test("Past two lines, the tail collapses into an N-more pill ahead of the +")
    func collapsesPastTwoLines() throws {
        let result = layout(pills: 10)
        #expect(result.hiddenCount > 0)
        #expect(result.pillFrames.count + result.hiddenCount == 10)
        #expect(result.height == Self.twoLines)
        let overflow = try #require(result.overflowFrame)
        let add = try #require(result.addFrame)
        #expect(overflow.minY == 28 + Self.gap)
        #expect(add.minY == 28 + Self.gap)
        #expect(add.minX > overflow.maxX)
        #expect(result.pillFrames.allSatisfy { $0.maxY <= Self.twoLines })
    }

    @Test("Hides only as many pills as the N-more pill needs room for")
    func hidesAsFewAsPossible() {
        // Two lines of 200 hold three 50pt pills each; the + (28) and "N more" (36) take a line-two slot.
        let result = layout(pills: 7)
        #expect(result.pillFrames.count == 5)
        #expect(result.hiddenCount == 2)
    }

    @Test("Expanded, every pill shows on as many lines as it takes")
    func expandedShowsAll() {
        let result = layout(pills: 10, maxLines: nil)
        #expect(result.hiddenCount == 0)
        #expect(result.pillFrames.count == 10)
        #expect(result.height > Self.twoLines)
    }

    @Test("A viewer who can't react gets the N-more pill without a +")
    func overflowWithoutAdd() {
        let result = layout(pills: 10, add: nil)
        #expect(result.addFrame == nil)
        #expect(result.overflowFrame != nil)
    }

    @Test("Trailing lines sit against the right edge")
    func trailingAlignment() {
        let result = layout(pills: 1, trailing: true)
        // The + (28) sits at the edge, and the pill (50) one gap before it.
        let pillX: CGFloat = 200 - 28 - Self.gap - 50
        #expect(result.addFrame?.maxX == 200)
        #expect(result.pillFrames.first?.minX == pillX)
    }
}
