//
//  FormattedChatListTimeTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
import FlipcashCore

/// Dates are built relative to `.now` at noon to keep them clear of midnight boundaries. The
/// "Yesterday" literal assumes the en_US test environment, as `FormattedRelativelyTests` does.
@Suite("Date.formattedChatListTime")
struct FormattedChatListTimeTests {

    private let calendar = Calendar.current

    private func daysAgo(_ days: Int) -> Date {
        let noonToday = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        return calendar.date(byAdding: .day, value: -days, to: noonToday)!
    }

    @Test("Today renders the time of day")
    func today() {
        #expect(daysAgo(0).formattedChatListTime().contains("12:00"))
    }

    @Test("Yesterday renders the localized relative day")
    func yesterday() {
        let date = daysAgo(1)
        #expect(date.formattedChatListTime() == DateFormatter.relativeDay.string(from: date))
        #expect(date.formattedChatListTime() == "Yesterday")
    }

    @Test("Dates two through six days ago render the short weekday", arguments: 2...6)
    func weekdayWithinTheWeek(daysAgo offset: Int) {
        let date = daysAgo(offset)
        let weekday = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
        #expect(date.formattedChatListTime() == weekday)
    }

    @Test("Dates older than a week render a short month and day")
    func olderThanAWeek() {
        #expect(daysAgo(30).formattedChatListTime().wholeMatch(of: /[A-Za-z]{3} \d{1,2}/) != nil)
    }
}
