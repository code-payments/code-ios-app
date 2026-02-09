//
//  Decimal+Operations.swift
//  FlipcashCore
//
//  Created by Raul Riera on 2026-02-07.
//

import Foundation

extension Decimal {
    public func rounded(to decimalPlaces: Int) -> Decimal {
        var current = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &current, decimalPlaces, .plain)
        return rounded
    }

    func roundedInt() -> Int {
        (rounded(to: 0) as NSDecimalNumber).intValue
    }

    private func pow10(_ n: Int) -> Decimal {
        var result: Decimal = 1
        for _ in 0..<n {
            result *= 10
        }
        return result
    }

    func scaleDown(_ d: Int) -> Decimal {
        return self / pow10(d)
    }
    
    func scaleUp(_ d: Int) -> Decimal {
        self * pow10(d)
    }

    func scaleUpInt(_ d: Int) -> UInt64 {
        let scaled = scaleUp(d)
        var rounded = Foundation.Decimal()
        var current = scaled
        // Use .plain (HALF_UP) rounding mode to match Kotlin's rounding behavior
        // .plain rounds to nearest, ties away from zero
        NSDecimalRound(&rounded, &current, 0, .plain)
        return NSDecimalNumber(decimal: rounded).uint64Value
    }
}
