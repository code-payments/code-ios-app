//
//  DateFormatter.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension DateFormatter {
    public static let relative: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()
    
    public static let relativeDay: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        f.doesRelativeDateFormatting = true
        return f
    }()
    
    public static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        f.doesRelativeDateFormatting = false
        return f
    }()
    
    public static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    public static let codeDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM dd"
        return f
    }()
}

extension Date {
    public func formattedTime() -> String {
        DateFormatter.timeFormatter.string(from: self)
    }
    
    /// "Today 12:13 PM" / "Yesterday 9:05 AM" / "Jun 18 4:30 PM".
    public func formattedChatSeparator() -> String {
        let day: String
        if Calendar.current.isDateInToday(self) {
            day = "Today"
        } else if Calendar.current.isDateInYesterday(self) {
            day = "Yesterday"
        } else {
            day = formatted(.dateTime.month().day())
        }
        return "\(day) \(formattedTime())"
    }

    /// The full time of a chat message for the menu header and the spoken description: "Today at
    /// 6:13 PM", "Yesterday at 6:13 PM", "Oct 21 at 6:13 PM", or "Oct 21, 2025 at 6:13 PM" outside
    /// the current year.
    public func formattedChatMessageTime(
        relativeTo now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let time = formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
        let day: String
        if calendar.isDate(self, inSameDayAs: now) {
            day = "Today"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(self, inSameDayAs: yesterday) {
            day = "Yesterday"
        } else {
            var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day()
            if !calendar.isDate(self, equalTo: now, toGranularity: .year) {
                style = style.year()
            }
            day = formatted(style)
        }
        return "\(day) at \(time)"
    }

    /// A chat's last activity for the chat list: the time today, the relative day for yesterday, a
    /// short weekday within the past week, and a short month and day before that.
    public func formattedChatListTime() -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(self) {
            return DateFormatter.relativeDay.string(from: self)
        }
        return self > Date.weekAgo()
            ? formatted(.dateTime.weekday(.abbreviated))
            : formatted(.dateTime.month(.abbreviated).day())
    }

    public func formattedRelatively(useTimeForToday: Bool = false) -> String {
        let calendar = Calendar.current
        let weekAgo = Date.weekAgo()
        
        if useTimeForToday, calendar.isDateInToday(self) {
            return DateFormatter.timeFormatter.string(from: self)
            
        } else if calendar.isDateInToday(self) || calendar.isDateInYesterday(self) {
            return DateFormatter.relativeDay.string(from: self)
            
        } else if self > weekAgo { // Within the last 6 days
            return DateFormatter.weekdayFormatter.string(from: self)
            
        } else {
            return DateFormatter.codeDateFormatter.string(from: self)
        }
    }
}

private extension Date {
    static func weekAgo() -> Date {
        let c = Calendar.current
        return c.date(byAdding: .day, value: -6, to: c.startOfDay(for: .now))!
    }
}
