//
//  TabBarBadgedIconTests.swift
//  FlipcashTests
//

import Testing
import UIKit
@testable import Flipcash

@MainActor
@Suite("Tab bar badged icon")
struct TabBarBadgedIconTests {

    @Test("nothing unread leaves the plain glyphs")
    func zeroCount_returnsNil() {
        #expect(TabBarBadgedIcon.itemImages(for: .chat, count: 0) == nil)
    }

    @Test("a count renders both states untinted by the bar")
    func count_rendersOriginalImages() throws {
        let images = try #require(TabBarBadgedIcon.itemImages(for: .chat, count: 3))

        #expect(images.normal.renderingMode == .alwaysOriginal)
        #expect(images.selected.renderingMode == .alwaysOriginal)
    }

    @Test("the bubble's overhang sits outside the glyph's alignment rect")
    func overhang_isExcludedFromAlignment() throws {
        let image = try #require(TabBarBadgedIcon.itemImages(for: .chat, count: 3)).normal

        #expect(image.alignmentRectInsets == UIEdgeInsets(top: 2, left: 0, bottom: 0, right: 2))
        #expect(image.size.width - 2 == 32)
        #expect(image.size.height - 2 == 32)
    }

    @Test("a new count renders new images")
    func newCount_rerenders() throws {
        let three = try #require(TabBarBadgedIcon.itemImages(for: .chat, count: 3))
        let four = try #require(TabBarBadgedIcon.itemImages(for: .chat, count: 4))

        #expect(three != four)
    }
}
