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
    
    public init(fiat: Decimal, currencyCode: CurrencyCode) throws {
        guard fiat >= 0 else {
            throw Error.invalidNegativeValue
        }
        
        self.init(
            quarks: fiat.toQuarks,
            currencyCode: currencyCode
        )
    }
    
    public init(fiat: Int, currencyCode: CurrencyCode) throws {
        guard fiat >= 0 else {
            throw Error.invalidNegativeValue
        }
        
        self.init(
            fiat: UInt64(fiat),
            currencyCode: currencyCode
        )
    }
    
    public init(fiat: UInt64, currencyCode: CurrencyCode) {
        self.init(
            quarks: fiat.toQuarks,
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
    public func formatted(suffix: String?) -> String {
        NumberFormatter.fiat(
            currency: currencyCode,
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
            fiat: Decimal(quarks).toFiat * rate.fx,
            currencyCode: rate.currency
        )
    }
}

// MARK: - ExpressibleByIntegerLiteral -

extension Fiat: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: UInt64) {
        self.init(fiat: value, currencyCode: .usd)
    }
}

extension Fiat: ExpressibleByFloatLiteral {
    public init(floatLiteral value: FloatLiteralType) {
        try! self.init(fiat: Decimal(value), currencyCode: .usd)
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
        NSDecimalNumber(decimal: self * .multiplier).uint64Value
    }
    
    var toFiat: Decimal {
        self / .multiplier
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
