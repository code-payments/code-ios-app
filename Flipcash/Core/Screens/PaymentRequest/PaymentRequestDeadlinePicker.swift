//
//  PaymentRequestDeadlinePicker.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Observation

/// The Time To Pay sheet's working choice: a preset or a custom day and time, picked from the days a
/// request can end on. Applied to the summary only on Done.
@MainActor
@Observable
final class PaymentRequestDeadlinePicker {

    /// The days in the grid, today's week first.
    static let gridDayCount = 35
    /// How many days past today the grid lets the user pick.
    static let lastDayOffset = 28
    /// The time a custom day starts at: 6:00 PM.
    static let defaultCustomTime = DateComponents(hour: 18, minute: 0)

    /// The choice Done applies.
    private(set) var choice: PaymentRequestDeadline

    let openedAt: Date
    let calendar: Calendar
    let locale: Locale

    /// The hour and minute the last custom day was given, kept when the user picks another day.
    private var customTime: DateComponents

    /// Opens on `deadline` at `now`, reading days in `calendar` and words in `locale`.
    init(deadline: PaymentRequestDeadline, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) {
        self.openedAt = now
        self.calendar = calendar
        self.locale = locale
        switch deadline {
        case .custom(let date):
            customTime = calendar.dateComponents([.hour, .minute], from: date)
        case .oneDay, .threeDays, .oneWeek, .twoWeeks, .fourWeeks:
            customTime = Self.defaultCustomTime
        }
        choice = deadline
    }

    // MARK: - Grid -

    /// The first day of today's week, by the calendar's first weekday.
    var gridStart: Date {
        calendar.dateInterval(of: .weekOfYear, for: openedAt)?.start ?? calendar.startOfDay(for: openedAt)
    }

    /// Every day in the grid, 5 rows of 7.
    var gridDays: [Date] {
        (0..<Self.gridDayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    var today: Date { calendar.startOfDay(for: openedAt) }

    /// The last day a request can end on.
    var lastDay: Date {
        calendar.date(byAdding: .day, value: Self.lastDayOffset, to: today) ?? today
    }

    /// Whether `day` can be tapped: today through today + 28 days.
    func isEnabled(_ day: Date) -> Bool {
        let start = calendar.startOfDay(for: day)
        return start >= today && start <= lastDay
    }

    /// The day the choice ends on.
    var selectedDay: Date {
        calendar.startOfDay(for: choice.endsAt(sentAt: openedAt))
    }

    /// The range's grey start circle: today, or nil when the choice closes today.
    var rangeStart: Date? {
        selectedDay > today ? today : nil
    }

    /// The part of the range band `day`'s cell draws, or nil when the band does not reach it.
    func band(for day: Date) -> RangeBand? {
        guard let start = rangeStart else { return nil }
        let day = calendar.startOfDay(for: day)
        guard day >= start, day <= selectedDay else { return nil }
        let column = gridDays.firstIndex(of: day).map { $0 % 7 }
        let fromCenter = day == start
        let toCenter = day == selectedDay
        return RangeBand(
            fromCenter: fromCenter,
            toCenter: toCenter,
            roundedLeading: !fromCenter && column == 0,
            roundedTrailing: !toCenter && column == 6
        )
    }

    /// The preset currently chosen, nil for a custom day.
    var selectedPreset: PaymentRequestDeadline? {
        switch choice {
        case .oneDay, .threeDays, .oneWeek, .twoWeeks, .fourWeeks: choice
        case .custom: nil
        }
    }

    // MARK: - Choosing -

    func select(_ preset: PaymentRequestDeadline) {
        choice = preset
    }

    /// Makes `day` the custom choice at the last custom time, 6:00 PM at first, moved inside the
    /// allowed range when it falls outside it.
    func select(day: Date) {
        guard isEnabled(day) else { return }
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = customTime.hour
        components.minute = customTime.minute
        let date = calendar.date(from: components) ?? day
        choice = .custom(clamped(date))
    }

    /// The custom date and time, or nil while a preset is chosen.
    var customDate: Date? {
        switch choice {
        case .custom(let date):                                    date
        case .oneDay, .threeDays, .oneWeek, .twoWeeks, .fourWeeks: nil
        }
    }

    /// Sets the custom time from the Time row and keeps it for later days.
    func setCustomDate(_ date: Date) {
        guard customDate != nil else { return }
        let clamped = clamped(date)
        customTime = calendar.dateComponents([.hour, .minute], from: clamped)
        choice = .custom(clamped)
    }

    /// The times the Time row offers on the chosen custom day.
    var customTimeRange: ClosedRange<Date> {
        let bounds = allowedRange
        guard let day = customDate.map({ calendar.startOfDay(for: $0) }),
              let dayEnd = calendar.date(byAdding: DateComponents(day: 1, minute: -1), to: day) else {
            return bounds
        }
        let lower = max(day, bounds.lowerBound)
        let upper = min(dayEnd, bounds.upperBound)
        return lower <= upper ? lower...upper : bounds
    }

    /// From an hour out to five minutes short of 28 days, each bound rounded to the minute inward.
    var allowedRange: ClosedRange<Date> {
        let range = PaymentRequestDeadline.customRange(openedAt: openedAt)
        let lower = roundedToMinute(range.lowerBound, up: true)
        let upper = roundedToMinute(range.upperBound, up: false)
        return lower...upper
    }

    private func clamped(_ date: Date) -> Date {
        let range = allowedRange
        return min(max(date, range.lowerBound), range.upperBound)
    }

    private func roundedToMinute(_ date: Date, up: Bool) -> Date {
        guard let minute = calendar.dateInterval(of: .minute, for: date)?.start else { return date }
        guard up, minute < date else { return minute }
        return minute.addingTimeInterval(60)
    }

    // MARK: - Starts / Closes -

    /// The Closes field: "≈ Mon, Nov 2" for a preset, "Thu, Nov 5, 6:00 PM" for a custom day.
    var closesValue: String {
        guard let date = customDate else { return "≈ \(dayText(choice.endsAt(sentAt: openedAt)))" }
        return "\(dayText(date)), \(timeText(date))"
    }

    /// The grey line under the fields: "1 Week · closes 7 days after you send", or "Custom · 10 days".
    var summaryLine: String {
        guard let date = customDate else {
            return "\(choice.rowTitle) · closes \(Self.days(presetDays)) after you send"
        }
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        return days == 0 ? "Custom · Today" : "Custom · \(Self.days(days))"
    }

    /// The Time row's value: "6:00 PM".
    func timeText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
    }

    /// A day's spoken name: "Thursday, November 5".
    func accessibilityDay(_ day: Date) -> String {
        day.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .weekday(.wide).month(.wide).day()
        )
    }

    private func dayText(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .weekday(.abbreviated).month(.abbreviated).day()
        )
    }

    private var presetDays: Int {
        switch choice {
        case .oneDay:    1
        case .threeDays: 3
        case .oneWeek:   7
        case .twoWeeks:  14
        case .fourWeeks: 28
        case .custom:    0
        }
    }

    private static func days(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }
}

/// The slice of the Time To Pay range band one grid cell draws.
struct RangeBand: Equatable {
    /// Starts at the cell's centre, under the grey start circle.
    var fromCenter: Bool
    /// Stops at the cell's centre, under the white closing circle.
    var toCenter: Bool
    /// Ends rounded at the row's leading edge, where the range wraps from the week before.
    var roundedLeading: Bool
    /// Ends rounded at the row's trailing edge, where the range wraps to the next week.
    var roundedTrailing: Bool
}
