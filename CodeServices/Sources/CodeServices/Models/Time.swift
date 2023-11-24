//
//  Time.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct Time {
    
    private let _milliseconds: Int64
    
    public static var now: Time {
        Time()
    }
    
    // MARK: - Init -
    
    public init() {
        self._milliseconds = Int64(Date().timeIntervalSince1970 * 1000.0)
    }
    
    private init(milliseconds: Int64) {
        self._milliseconds = milliseconds
    }
}

// MARK: - Operators -

extension Time {
    public static func + (lhs: Time, rhs: Interval) -> Time {
        Time(milliseconds: lhs._milliseconds + rhs.milliseconds)
    }
    
    public static func - (lhs: Time, rhs: Interval) -> Time {
        Time(milliseconds: lhs._milliseconds - rhs.milliseconds)
    }
    
    public static func - (lhs: Time, rhs: Time) -> Interval {
        Time.Interval(milliseconds: rhs._milliseconds - lhs._milliseconds)
    }
}

// MARK: - Interval -

extension Time {
    public struct Interval {
        
        public let milliseconds: Int64
        
        public var negated: Interval {
            Interval(milliseconds: milliseconds * -1)
        }
        
        // MARK: - Init -
        
        fileprivate init(milliseconds: Int64) {
            self.milliseconds = milliseconds
        }
        
        // MARK: - Initializers -
        
        public static func seconds(_ value: Int) -> Interval {
            Interval(milliseconds: Int64(value * 1000))
        }
        
        public static func milliseconds(_ value: Int) -> Interval {
            Interval(milliseconds: Int64(value))
        }
    }
}

// MARK: - Accessors -

extension Time.Interval {
    public var nanoseconds: Int64 {
        milliseconds * 1_000_000
    }
    
    public var seconds: TimeInterval {
        TimeInterval(milliseconds) / 1000.0
    }
}
