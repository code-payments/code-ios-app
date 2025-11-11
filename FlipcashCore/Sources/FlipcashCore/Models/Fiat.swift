//
//  Fiat.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct Fiat: Equatable, Hashable, Codable, Sendable {
    
    public let quarks: UInt64
    public let currencyCode: CurrencyCode
    public let decimals: Int
    
    public var decimalValue: Decimal {
        quarks.scaleDown(decimals)
    }
    
    public var doubleValue: Double {
        decimalValue.doubleValue
    }
    
    // MARK: - Init -
    
    public init(quarks: UInt64, currencyCode: CurrencyCode, decimals: Int) {
        self.quarks = quarks
        self.currencyCode = currencyCode
        self.decimals = decimals
    }
    
    public init(fiatDecimal: Decimal, currencyCode: CurrencyCode, decimals: Int) throws {
        guard fiatDecimal >= 0 else {
            throw Error.invalidNegativeValue
        }
        
        self.init(
            quarks: fiatDecimal.scaleUpInt(decimals),
            currencyCode: currencyCode,
            decimals: decimals
        )
    }
    
    public init(fiatInt: Int, currencyCode: CurrencyCode, decimals: Int) throws {
        guard fiatInt >= 0 else {
            throw Error.invalidNegativeValue
        }
        
        self.init(
            fiatUnsigned: UInt64(fiatInt),
            currencyCode: currencyCode,
            decimals: decimals
        )
    }
    
    public init(fiatUnsigned: UInt64, currencyCode: CurrencyCode, decimals: Int) {
        self.init(
            quarks: fiatUnsigned.scaleDownInt(decimals),
            currencyCode: currencyCode,
            decimals: decimals
        )
    }
    
    public init(quarks: Int64, currencyCode: CurrencyCode, decimals: Int) throws {
        guard quarks >= 0 else {
            throw Error.invalidNegativeValue
        }
        
        self.init(
            quarks: UInt64(quarks),
            currencyCode: currencyCode,
            decimals: decimals
        )
    }
    
    public static func zero(currencyCode: CurrencyCode, decimals: Int) -> Fiat {
        Fiat(
            quarks: 0 as UInt64,
            currencyCode: currencyCode,
            decimals: decimals
        )
    }
    
    // MARK: - Operations -
    
    public func adding(_ value: Fiat) throws -> Fiat {
        guard value.currencyCode == currencyCode else {
            throw Error.currencyCodeMismatch
        }
        
        guard value.decimals == decimals else {
            throw Error.decimalMismatch
        }
        
        return .init(
            quarks: quarks + value.quarks,
            currencyCode: currencyCode,
            decimals: decimals
        )
    }
    
    public func subtracting(_ value: Fiat) throws -> Fiat {
        guard value.currencyCode == currencyCode else {
            throw Error.currencyCodeMismatch
        }
        
        guard value.decimals == decimals else {
            throw Error.decimalMismatch
        }
        
        guard quarks >= value.quarks else {
            throw Error.invalidNegativeValue
        }
        
        return Fiat(
            quarks: quarks - value.quarks,
            currencyCode: currencyCode,
            decimals: decimals
        )
    }
    
    public func subtractingScaled(_ value: Fiat) throws -> Fiat {
        guard value.currencyCode == currencyCode else {
            throw Error.currencyCodeMismatch
        }
        
        let (lhs, rhs, decimals) = try align(with: value)
        
        guard lhs.quarks >= rhs.quarks else {
            throw Error.invalidNegativeValue
        }
        
        return Fiat(
            quarks: lhs.quarks - rhs.quarks,
            currencyCode: currencyCode,
            decimals: decimals
        )
    }
    
    /// Returns a copy of this Fiat scaled to `targetDecimals`.
    /// If `targetDecimals` is greater than `decimals`, quarks are scaled up.
    /// If smaller, quarks are scaled down. Currency code is preserved.
    private func scaled(to targetDecimals: Int) -> Fiat {
        if targetDecimals == decimals {
            return self
        } else if targetDecimals > decimals {
            let diff = targetDecimals - decimals
            return Fiat(
                quarks: quarks.scaleUp(diff),
                currencyCode: currencyCode,
                decimals: targetDecimals
            )
        } else {
            let diff = decimals - targetDecimals
            return Fiat(
                quarks: quarks.scaleDownInt(diff),
                currencyCode: currencyCode,
                decimals: targetDecimals
            )
        }
    }

    /// Aligns `self` and `other` to a common decimal precision (the maximum of the two).
    /// - Returns: `(lhs, rhs, targetDecimals)` where both amounts are scaled to `targetDecimals`.
    /// - Throws: `Error.currencyCodeMismatch` if the currency codes differ.
    private func align(with other: Fiat) throws -> (lhs: Fiat, rhs: Fiat, decimals: Int) {
        guard other.currencyCode == currencyCode else {
            throw Error.currencyCodeMismatch
        }
        
        let target = max(self.decimals, other.decimals)
        
        return (
            self.scaled(to: target),
            other.scaled(to: target),
            target
        )
    }
    
    // MARK: - Fee -
    
    public func calculateFee(bps: Int) -> Fiat {
        Fiat(
            quarks: quarks * UInt64(bps) / 10_000,
            currencyCode: currencyCode,
            decimals: decimals
        )
    }
}

// MARK: - Errors -

extension Fiat {
    public enum Error: Swift.Error {
        case invalidNegativeValue
        case currencyCodeMismatch
        case decimalMismatch
    }
}

// MARK: - Formatting -

extension Fiat {
    public func formatted(showAllDecimals: Bool = false, truncated: Bool = false, suffix: String? = nil) -> String {
        let digits = showAllDecimals ? 6 : currencyCode.maximumFractionDigits
        return NumberFormatter.fiat(
            currency: currencyCode,
            minimumFractionDigits: digits,
            maximumFractionDigits: digits,
            truncated: truncated,
            suffix: suffix
        ).string(from: quarks.scaleDown(decimals))!
    }
}

// MARK: - Description -

extension Fiat: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        formatted(suffix: nil)
    }
    
    public var debugDescription: String {
        description
    }
}

// MARK: - Fiat -

extension Fiat {
    public func converting(to rate: Rate, decimals: Int) -> Fiat {
        try! Fiat(
            fiatDecimal: Decimal(quarks).scaleDown(decimals) * rate.fx,
            currencyCode: rate.currency,
            decimals: decimals
        )
    }
}

// MARK: - ExpressibleByIntegerLiteral -

extension Fiat: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: UInt64) {
        self.init(fiatUnsigned: value, currencyCode: .usd, decimals: 6)
    }
}

extension Fiat: ExpressibleByFloatLiteral {
    public init(floatLiteral value: FloatLiteralType) {
        try! self.init(fiatDecimal: Decimal(value), currencyCode: .usd, decimals: 6)
    }
}

// MARK: - Comparable -

extension Fiat: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        do {
            let (l, r, _) = try lhs.align(with: rhs)
            return l.quarks < r.quarks
        } catch {
            assertionFailure("Attempting to compare different currency Fiat values.")
            print(error)
            return false
        }
    }
        
//    public static func < (lhs: Self, rhs: Self) -> Bool {
//        lhs.quarks < rhs.quarks
//    }
//    
//    public static func <= (lhs: Self, rhs: Self) -> Bool {
//        lhs.quarks <= rhs.quarks
//    }
//    
//    public static func >= (lhs: Self, rhs: Self) -> Bool {
//        lhs.quarks >= rhs.quarks
//    }
//    
//    public static func > (lhs: Self, rhs: Self) -> Bool {
//        lhs.quarks > rhs.quarks
//    }
}

// MARK: - Operations -

//extension Fiat {
//    public static func + (lhs: Self, rhs: Self) -> Fiat {
//        Fiat(quarks: lhs.quarks + rhs.quarks)
//    }
//    
//    public static func - (lhs: Self, rhs: Self) -> Fiat {
//        guard lhs >= rhs else {
//            return 0
//        }
//        return Fiat(quarks: lhs.quarks - rhs.quarks)
//    }
//    
//    public static func * (lhs: Self, rhs: Int) -> Fiat {
//        Fiat(quarks: lhs.quarks * UInt64(rhs))
//    }
//
//    public static func / (lhs: Self, rhs: Int) -> Int {
//        Int((lhs.quarks / UInt64(rhs)).toFiatTruncating)
//    }
//}

// MARK: - Decimal -

//private extension Decimal {
//    
//    static let multiplier: Decimal = 1_000_000
//    
//    var toQuarks: UInt64 {
//        let rounded = (self * .multiplier).rounded(to: 0)
//        return NSDecimalNumber(decimal: rounded).uint64Value
//    }
//    
//    var toFiat: Decimal {
//        self / .multiplier
//    }
//}

extension Decimal {
    public func rounded(to decimalPlaces: Int) -> Decimal {
        var current = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &current, decimalPlaces, .plain)
        return rounded
    }
}

//private extension UInt64 {
//    
//    static let multiplier: UInt64 = 1_000_000
//    
//    var toQuarks: UInt64 {
//        self * .multiplier
//    }
//    
//    var toFiat: Decimal {
//        Decimal(self) / .multiplier
//    }
//}

extension UInt64 {
    private func pow10(_ n: Int) -> UInt64 {
        return (0..<n).reduce(1) { acc, _ in acc * 10 }
    }
    
    func scaleDown(_ d: Int) -> Decimal {
        let factor = Decimal(pow10(d))
        return Decimal(self) / factor
    }
    
    func scaleDownInt(_ d: Int) -> UInt64 {
        let factor = pow10(d)
        return self / factor
    }

    func scaleUp(_ d: Int) -> UInt64 {
        let factor = pow10(d)
        return self * factor
    }
}

extension Decimal {
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
        UInt64(scaleUp(d).doubleValue)
    }
}
