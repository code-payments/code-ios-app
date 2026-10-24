//
//  ChatTimestampRevealTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@Suite("Timestamp reveal")
@MainActor
struct ChatTimestampRevealTests {

    @Test("A mostly-horizontal leading drag may begin")
    func leadingDrag_begins() {
        #expect(ChatTimestampReveal.shouldBegin(velocity: CGPoint(x: -300, y: 40), isBlocked: false))
    }

    @Test("A trailing drag is the reply swipe's, not the reveal's")
    func trailingDrag_doesNotBegin() {
        #expect(ChatTimestampReveal.shouldBegin(velocity: CGPoint(x: 300, y: 10), isBlocked: false) == false)
        #expect(ChatSwipeToReply.shouldBegin(velocity: CGPoint(x: -300, y: 10), isBlocked: false) == false)
    }

    @Test("A mostly-vertical drag is left to the scroll view")
    func verticalDrag_doesNotBegin() {
        #expect(ChatTimestampReveal.shouldBegin(velocity: CGPoint(x: -40, y: -300), isBlocked: false) == false)
        #expect(ChatTimestampReveal.shouldBegin(velocity: CGPoint(x: -120, y: 160), isBlocked: false) == false)
    }

    @Test("Nothing begins while the transcript is blocked")
    func blocked_doesNotBegin() {
        #expect(ChatTimestampReveal.shouldBegin(velocity: CGPoint(x: -300, y: 40), isBlocked: true) == false)
    }

    @Test("A trailing translation reveals nothing")
    func trailingTranslation_isZero() {
        #expect(ChatTimestampReveal.offset(forTranslation: 0) == 0)
        #expect(ChatTimestampReveal.offset(forTranslation: 50) == 0)
    }

    @Test("The bubbles follow the finger for half the column")
    func translation_tracksTheFinger() {
        let half = ChatTimestampReveal.travel / 2
        #expect(ChatTimestampReveal.offset(forTranslation: -20) == 20)
        #expect(ChatTimestampReveal.offset(forTranslation: -half) == half)
    }

    @Test("Past half the column the drag resists, and never passes the column's travel")
    func translation_resistsAndCaps() {
        let width = ChatTimestampReveal.travel
        let half = width / 2
        let resisted = ChatTimestampReveal.offset(forTranslation: -(half + 20))
        #expect(resisted > half)
        #expect(resisted < half + 20)
        #expect(ChatTimestampReveal.offset(forTranslation: -10_000) <= width)
        #expect(ChatTimestampReveal.offset(forTranslation: -10_000) > width - 1)
    }

    @Test("The offset grows with the drag")
    func translation_isMonotonic() {
        var previous: CGFloat = 0
        for travel in stride(from: CGFloat(0), through: 400, by: 10) {
            let offset = ChatTimestampReveal.offset(forTranslation: -travel)
            #expect(offset >= previous)
            previous = offset
        }
    }

    @Test("A deleted row and a row with no send time show no time in the column")
    func revealedTime_skipsRowsWithoutTime() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let deleted = ChatMessage(id: "a", content: .deleted("This message was deleted"), sender: .me, sentAt: date)
        let untimed = ChatMessage(id: "b", text: "hi", sender: .other)
        let timed = ChatMessage(id: "c", text: "hi", sender: .other, sentAt: date)
        #expect(ChatColumnCell.revealedTime(for: deleted) == nil)
        #expect(ChatColumnCell.revealedTime(for: untimed) == nil)
        #expect(ChatColumnCell.revealedTime(for: timed) == date.formattedTime())
    }
}

@Suite("Message menu header")
@MainActor
struct MessageMenuHeaderTests {

    @Test("A header adds one row of height and none of width")
    func header_isMeasured() {
        let actions = [UIAction(title: "Reply") { _ in }, UIAction(title: "Copy") { _ in }]
        let plain = MessageMenuView.size(for: actions)
        let headed = MessageMenuView.size(for: actions, header: "Today at 6:13 PM")
        #expect(headed.width == plain.width)
        #expect(headed.height > plain.height)
        #expect(MessageMenuView(actions: actions, header: "Today at 6:13 PM").bounds.size == headed)
    }

    @Test("Releasing over the header selects nothing")
    func header_isNotARow() {
        let actions = [UIAction(title: "Reply") { _ in }]
        let menu = MessageMenuView(actions: actions, header: "Today at 6:13 PM")
        var selected: UIAction?
        menu.onSelect = { selected = $0 }
        #expect(menu.release(at: CGPoint(x: 40, y: 20)) == false)
        #expect(selected == nil)
    }
}

@Suite("Message full time")
struct ChatMessageFullTimeTests {

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()
    private static let locale = Locale(identifier: "en_US")

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static let now = date(2026, 10, 23, 20, 0)

    private func format(_ date: Date) -> String {
        date.formattedChatMessageTime(relativeTo: Self.now, calendar: Self.calendar, locale: Self.locale)
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test("A message from today reads Today at its time")
    func today() {
        #expect(format(Self.date(2026, 10, 23, 18, 13)) == "Today at 6:13 PM")
    }

    @Test("A message from yesterday reads Yesterday at its time")
    func yesterday() {
        #expect(format(Self.date(2026, 10, 22, 9, 5)) == "Yesterday at 9:05 AM")
    }

    @Test("An older message this year reads its month and day")
    func olderThisYear() {
        #expect(format(Self.date(2026, 10, 21, 18, 13)) == "Oct 21 at 6:13 PM")
    }

    @Test("A message from another year carries the year")
    func otherYear() {
        #expect(format(Self.date(2025, 10, 21, 18, 13)) == "Oct 21, 2025 at 6:13 PM")
    }
}
