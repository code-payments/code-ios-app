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
    
    public var decimalValue: Decimal {
        quarks.toFiat
    }
    
    public var doubleValue: Double {
        decimalValue.doubleValue
    }
    
    // MARK: - Init -
    
    public init(quarks: UInt64, currencyCode: CurrencyCode) {
        self.quarks = quarks
        self.currencyCode = currencyCode
    }
    
    public init(fiatDecimal: Decimal, currencyCode: CurrencyCode) throws {
        guard fiatDecimal >= 0 else {
            throw Error.invalidNegativeValue
        }
        
        self.init(
            quarks: fiatDecimal.toQuarks,
            currencyCode: currencyCode
        )
    }
    
    public init(fiatInt: Int, currencyCode: CurrencyCode) throws {
        guard fiatInt >= 0 else {
            throw Error.invalidNegativeValue
        }
        
        self.init(
            fiatUnsigned: UInt64(fiatInt),
            currencyCode: currencyCode
        )
    }
    
    public init(fiatUnsigned: UInt64, currencyCode: CurrencyCode) {
        self.init(
            quarks: fiatUnsigned.toQuarks,
            currencyCode: currencyCode
        )
    }
    
    public init(quarks: Int64, currencyCode: CurrencyCode) throws {
        guard quarks >= 0 else {
            throw Error.invalidNegativeValue
        }
        
        self.init(
            quarks: UInt64(quarks),
            currencyCode: currencyCode
        )
    }
    
    // MARK: - Fee -
    
    public func calculateFee(bps: Int) -> Fiat {
        Fiat(
            quarks: quarks * UInt64(bps) / 10_000,
            currencyCode: currencyCode
        )
    }
}

// MARK: - Errors -

extension Fiat {
    enum Error: Swift.Error {
        case invalidNegativeValue
    }
}

// MARK: - Formatting -

extension Fiat {
    public func formattedWithSuffixIfNeeded() -> String {
        if currencyCode == .usd {
            formatted(suffix: nil)
        } else {
            formatted(suffix: " of USD")
        }
    }
    
    public func formatted(showAllDecimals: Bool = false, suffix: String?) -> String {
        NumberFormatter.fiat(
            currency: currencyCode,
            minimumFractionDigits: showAllDecimals ? 6 : 2,
            truncated: false,
            suffix: suffix
        ).string(from: quarks.toFiat)!
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
    public func converting(to rate: Rate) -> Fiat {
        try! Fiat(
            fiatDecimal: Decimal(quarks).toFiat * rate.fx,
            currencyCode: rate.currency
        )
    }
}

// MARK: - ExpressibleByIntegerLiteral -

extension Fiat: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: UInt64) {
        self.init(fiatUnsigned: value, currencyCode: .usd)
    }
}

extension Fiat: ExpressibleByFloatLiteral {
    public init(floatLiteral value: FloatLiteralType) {
        try! self.init(fiatDecimal: Decimal(value), currencyCode: .usd)
    }
}

// MARK: - Comparable -

extension Fiat: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.quarks < rhs.quarks
    }
    
    public static func <= (lhs: Self, rhs: Self) -> Bool {
        lhs.quarks <= rhs.quarks
    }
    
    public static func >= (lhs: Self, rhs: Self) -> Bool {
        lhs.quarks >= rhs.quarks
    }
    
    public static func > (lhs: Self, rhs: Self) -> Bool {
        lhs.quarks > rhs.quarks
    }
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

private extension Decimal {
    
    static let multiplier: Decimal = 1_000_000
    
    var toQuarks: UInt64 {
        let rounded = (self * .multiplier).rounded(to: 0)
        return NSDecimalNumber(decimal: rounded).uint64Value
    }
    
    var toFiat: Decimal {
        self / .multiplier
    }
}

extension Decimal {
    func rounded(to decimalPlaces: Int) -> Decimal {
        var current = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &current, decimalPlaces, .plain)
        return rounded
    }
}

private extension UInt64 {
    
    static let multiplier: UInt64 = 1_000_000
    
    var toQuarks: UInt64 {
        self * .multiplier
    }
    
    var toFiat: Decimal {
        Decimal(self) / .multiplier
    }
}
