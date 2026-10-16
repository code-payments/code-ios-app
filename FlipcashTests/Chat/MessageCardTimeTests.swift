import Foundation
import Testing
@testable import Flipcash

@Suite struct MessageCardTimeTests {

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private static let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 15))!

    private static func time(_ date: Date) -> String {
        LinkCardResolver.relativeTime(of: date, now: now, calendar: calendar)
    }

    @Test func underAMinuteIsNow() {
        #expect(Self.time(Self.now.addingTimeInterval(-20)) == "now")
    }

    @Test func sameDayCountsMinutesThenHours() {
        #expect(Self.time(Self.now.addingTimeInterval(-45 * 60)) == "45m")
        #expect(Self.time(Self.now.addingTimeInterval(-2 * 3600 - 59)) == "2h")
    }

    @Test func dayBeforeIsYesterday() {
        #expect(Self.time(Self.now.addingTimeInterval(-20 * 3600)) == "Yesterday")
    }

    @Test func thisYearOmitsTheYear() {
        let date = Self.calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 9))!
        #expect(Self.time(date) == "Oct 9")
    }

    @Test func earlierYearKeepsTheYear() {
        let date = Self.calendar.date(from: DateComponents(year: 2025, month: 10, day: 9, hour: 9))!
        #expect(Self.time(date) == "Oct 9, 2025")
    }
}
