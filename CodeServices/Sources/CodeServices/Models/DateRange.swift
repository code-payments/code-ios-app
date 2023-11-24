//
//  DateRange.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct DateRange {
    
    public var start: Date
    public var end: Date?
    
    public init(start: Date, end: Date? = nil) {
        self.start = start
        self.end = end
    }
}

extension DateRange {
    public enum Interval {
        case raw
        case hour
        case day
        case week
        case month
    }
}

// MARK: - Date Conveniences -

extension Date {
    public static func now() -> Date {
        Date()
    }
    
    public static func todayAtMidnight() -> Date {
        Calendar.current.startOfDay(for: .now())
    }
    
    public func adding(seconds: Int) -> Date {
        Date(timeIntervalSince1970: timeIntervalSince1970 + Double(seconds))
    }
    
    public func adding(minutes: Int) -> Date {
        adding(seconds: 60 * minutes)
    }
    
    public func adding(hours: Int) -> Date {
        adding(minutes: 60 * hours)
    }
    
    public func adding(days: Int) -> Date {
        adding(hours: 24 * days)
    }
}
