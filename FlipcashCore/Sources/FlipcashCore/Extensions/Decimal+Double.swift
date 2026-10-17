//
//  Decimal+Double.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Decimal {

    /// The nearest `Double` to this value, matching Android's `BigDecimal.toDouble()`.
    ///
    /// `native_amount` in intent exchange data is a double, so both platforms must land on the
    /// same one. `NSDecimalNumber.doubleValue` scales the mantissa by ten once per decimal digit
    /// and can miss by an ulp or more (0.007 becomes 0.006999999999999999). `description` is
    /// locale-independent and `Double(String)` rounds correctly.
    public var doubleValue: Double {
        if _length == 0 {
            return _isNegative == 1 ? Double.nan : 0
        }
        return Double(description) ?? NSDecimalNumber(decimal: self).doubleValue
    }
}
