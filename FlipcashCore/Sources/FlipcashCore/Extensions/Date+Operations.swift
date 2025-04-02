//
//  Date+Operations.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Date {
    public static func todayAtMidnight() -> Date {
        Calendar.current.startOfDay(for: .now)
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
