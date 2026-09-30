//
//  MessageLiftLayoutTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import CoreGraphics
@testable import FlipcashUI

@Suite("Message lift layout")
struct MessageLiftLayoutTests {

    private static let screen = CGRect(x: 0, y: 0, width: 402, height: 874)
    private static let safeArea: (top: CGFloat, bottom: CGFloat) = (62, 34)
    private static let strip: CGFloat = 55
    private static let gap: CGFloat = 16
    private static let menu = CGSize(width: 250, height: 176)

    private var top: CGFloat { Self.safeArea.top + MessageLiftLayout.edgeMargin }
    private var bottom: CGFloat { Self.screen.height - Self.safeArea.bottom - MessageLiftLayout.edgeMargin }

    private func layout(_ bubble: CGRect, strip: Bool = true, menu: Bool = true) -> MessageLiftLayout {
        MessageLiftLayout(
            bubble: bubble,
            bounds: Self.screen,
            safeArea: Self.safeArea,
            stripHeight: strip ? Self.strip : nil,
            stripGap: Self.gap,
            menuSize: menu ? Self.menu : nil
        )
    }

    @Test("A bubble with room on both sides stays in its row")
    func middleBubbleStays() {
        let bubble = CGRect(x: 250, y: 400, width: 136, height: 40)
        let lift = layout(bubble)
        #expect(lift.bubble == bubble)
        #expect(lift.stripTop == bubble.minY - Self.gap - Self.strip)
        #expect(lift.menu?.minY == bubble.maxY + MessageLiftLayout.menuGap)
    }

    @Test("A bubble near the top moves down just far enough for the strip")
    func topBubbleMakesRoomForStrip() {
        let lift = layout(CGRect(x: 16, y: 90, width: 200, height: 40))
        #expect(lift.stripTop == top)
        #expect(lift.bubble.minY == top + Self.strip + Self.gap)
    }

    @Test("A bubble near the bottom moves up just far enough for the menu below it")
    func bottomBubbleKeepsMenuBelow() throws {
        let lift = layout(CGRect(x: 250, y: 760, width: 136, height: 40))
        let menu = try #require(lift.menu)
        #expect(menu.maxY == bottom)
        #expect(menu.minY > lift.bubble.maxY)
        #expect(try #require(lift.stripTop) < lift.bubble.minY)
    }

    @Test("A bubble too tall for the screen scales down toward its own side and keeps everything on screen")
    func tallBubbleScales() throws {
        let bubble = CGRect(x: 100, y: 80, width: 286, height: 900)
        let lift = layout(bubble)
        #expect(lift.bubble.height < bubble.height)
        #expect(abs(lift.bubble.maxX - bubble.maxX) < 0.001)
        #expect(lift.stripTop == top)
        #expect(abs(try #require(lift.menu).maxY - bottom) < 0.001)
    }

    @Test("A menu wider than an incoming bubble lines up with the bubble's leading edge")
    func incomingMenuHugsLeading() {
        let bubble = CGRect(x: 16, y: 400, width: 60, height: 40)
        #expect(layout(bubble).menu?.minX == bubble.minX)
    }

    @Test("A menu wider than an outgoing bubble lines up with its trailing edge")
    func outgoingMenuHugsTrailing() {
        let bubble = CGRect(x: 326, y: 400, width: 60, height: 40)
        #expect(layout(bubble).menu?.maxX == bubble.maxX)
    }

    @Test("A menu-less lift can sit as low as the safe area allows")
    func stripOnlyUsesTheBottom() {
        let bubble = CGRect(x: 250, y: 760, width: 136, height: 40)
        let lift = layout(bubble, menu: false)
        #expect(lift.bubble == bubble)
        #expect(lift.menu == nil)
    }
}
