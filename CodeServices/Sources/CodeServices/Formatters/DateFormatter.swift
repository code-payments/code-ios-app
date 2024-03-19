//
//  DateFormatter.swift
//  CodeServices
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
    
    public static let relativeTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
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
    
    public func formattedRelatively() -> String {
        let calendar = Calendar.current
        let weekAgo = Date.weekAgo()
        
        if calendar.isDateInToday(self) {
            return DateFormatter.timeFormatter.string(from: self)
            
        } else if calendar.isDateInYesterday(self) {
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
        return c.date(byAdding: .day, value: -6, to: c.startOfDay(for: .now()))!
    }
}
