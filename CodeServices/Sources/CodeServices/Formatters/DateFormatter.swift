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
}

extension Date {
    public func formattedRelatively() -> String {
        let isFresh = self.distance(to: .now()) < 60 * 60 * 12 // 12 hours
        if isFresh {
            return DateFormatter.relativeTime.string(from: self)
        } else {
            return DateFormatter.relativeDay.string(from: self)
        }
    }
}
