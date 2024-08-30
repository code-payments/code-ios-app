//
//  Curve.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

enum Curve {
    static func ease(value: Double, from inputRange: ClosedRange<Double>, to outputRange: ClosedRange<Double>, easeIn: Bool, easeOut: Bool) -> Double {
        let normalizedValue = (value - inputRange.lowerBound) / (inputRange.upperBound - inputRange.lowerBound)
        
        let easedValue: Double
        
        if easeIn && easeOut {
            if normalizedValue < 0.5 {
                easedValue = 4 * pow(normalizedValue, 3)
            } else {
                easedValue = 1 - pow(-2 * normalizedValue + 2, 3) / 2
            }
        } else if easeIn {
            easedValue = pow(normalizedValue, 3)
            
        } else if easeOut {
            
            easedValue = 1 - pow(1 - normalizedValue, 3)
            
        } else {
            easedValue = normalizedValue
        }
        
        return easedValue * (outputRange.upperBound - outputRange.lowerBound) + outputRange.lowerBound
    }
}
