//
//  FormattedRelativelyTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
import FlipcashCore

/// `formattedRelatively` buckets a date relative to the current day, so dates are built relative
/// to `.now` at noon to keep them clear of midnight boundaries. The literal day/time strings assume
/// the en_US test environment; the weekday case derives its expectation independently so it holds
/// in any locale.
@Suite("Date.formattedRelatively")
struct FormattedRelativelyTests {

    private let calendar = Calendar.current

    private func daysAgo(_ days: Int) -> Date {
        let noonToday = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        return calendar.date(byAdding: .day, value: -days, to: noonToday)!
    }

    @Test("Today renders the relative day, or the time of day when requested")
    func today() {
        let noonToday = daysAgo(0)
        #expect(noonToday.formattedRelatively() == "Today")
        // The time of day, not the relative day. The exact AM/PM separator and 12-/24-hour shape
        // are locale-dependent, so assert the noon time is present rather than a fixed literal.
        let withTime = noonToday.formattedRelatively(useTimeForToday: true)
        #expect(withTime != "Today")
        #expect(withTime.contains("12:00"))
    }

    @Test("Yesterday renders the relative day whether or not the time is requested")
    func yesterday() {
        let date = daysAgo(1)
        #expect(date.formattedRelatively() == "Yesterday")
        #expect(date.formattedRelatively(useTimeForToday: true) == "Yesterday")
    }

    @Test("Dates two through six days ago render the weekday name", arguments: 2...6)
    func weekdayWithinTheWeek(daysAgo offset: Int) {
        let date = daysAgo(offset)
        let weekday = calendar.weekdaySymbols[calendar.component(.weekday, from: date) - 1]
        #expect(date.formattedRelatively() == weekday)
    }

    @Test("Dates older than a week render an abbreviated weekday, month, and day")
    func olderThanAWeek() {
        let result = daysAgo(30).formattedRelatively()
        #expect(result.wholeMatch(of: /[A-Za-z]{3}, [A-Za-z]{3} \d{2}/) != nil)
    }
}
