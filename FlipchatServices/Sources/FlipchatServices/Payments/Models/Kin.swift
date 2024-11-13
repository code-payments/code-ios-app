//
//  Kin.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct Kin: Equatable, Hashable, Codable, Sendable {
    
    public let quarks: UInt64
    
#if DEBUG
    public let truncatedKinValue: UInt64
#else
    public var truncatedKinValue: UInt64 {
        quarks.toKinTruncating
    }
#endif
    
    public var fractionalQuarks: UInt64 {
        quarks - quarks.toKinTruncating.toQuarks
    }
    
    public var hasWholeKin: Bool {
        truncatedKinValue > 0
    }
    
    // MARK: - Init -
    
    public init?(kin: Decimal) {
        guard kin >= 0 else {
            return nil
        }
        
        self.init(
            quarks: kin.roundedUpToNearestQuark().toQuarks
        )
    }
    
    public init?(kin: Int) {
        guard kin >= 0 else {
            return nil
        }
        
        self.init(kin: UInt64(kin))
    }
    
    public init(kin: UInt64) {
        self.init(quarks: kin.toQuarks)
    }
    
    public init?(quarks: Int64) {
        guard quarks >= 0 else {
            return nil
        }
        
        self.init(quarks: UInt64(quarks))
    }
    
    public init(quarks: UInt64) {
        self.quarks = quarks
#if DEBUG
        self.truncatedKinValue = quarks.toKinTruncating
#endif
    }
    
    // MARK: - Truncation -
    
    public func truncating() -> Kin {
        Kin(kin: truncatedKinValue)
    }
    
    // MARK: - Inflation -
    
    public func inflating() -> Kin {
        if fractionalQuarks > 0 {
            return Kin(kin: truncatedKinValue) + 1
        }
        return self
    }
}

extension Kin {
    public func calculateFee(bps: Int) -> Kin {
        Kin(quarks: quarks * UInt64(bps) / 10_000)
            // Truncate to remove support
            // for fraction fee values
            //.truncating()
    }
}

// MARK: - Formatting -

extension Kin {
    public func formattedTruncatedKin() -> String {
        NumberFormatter.kin.string(from: truncatedKinValue)!
    }
    
    public func formattedFiat(rate: Rate, truncated: Bool = false, suffix: String?) -> String {
        formattedFiat(fx: rate.fx, currency: rate.currency, truncated: truncated, suffix: suffix)
    }
    
    public func formattedFiat(fx: Decimal, currency: CurrencyCode, truncated: Bool = false, suffix: String?) -> String {
        NumberFormatter.fiat(
            currency: currency,
            truncated: truncated,
            suffix: suffix
        ).string(from: toFiat(fx: fx))!
    }
}

// MARK: - Description -

extension Kin: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "K \(quarks.toKinTruncating) (\(fractionalQuarks))"
    }
    
    public var debugDescription: String {
        description
    }
}

// MARK: - Fiat -

extension Kin {
    public func toFiat(fx: Decimal) -> Decimal {
        Decimal(quarks).toKin * fx
    }
    
    public static func fromFiat(fiat: Decimal, fx: Decimal) -> Kin {
        Kin(kin: fiat / fx)!
    }
}

// MARK: - ExpressibleByIntegerLiteral -

extension Kin: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: UInt64) {
        self.init(kin: value)
    }
}

// MARK: - Comparable -

extension Kin: Comparable {
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

extension Kin {
    public static func + (lhs: Self, rhs: Self) -> Kin {
        Kin(quarks: lhs.quarks + rhs.quarks)
    }

//    public static func + (lhs: Self, rhs: Int) -> Kin {
//        Kin(quarks: lhs.quarks + UInt64(rhs))
//    }
    
    public static func - (lhs: Self, rhs: Self) -> Kin {
        guard lhs >= rhs else {
            return 0
        }
        return Kin(quarks: lhs.quarks - rhs.quarks)
    }
    
//    public static func - (lhs: Self, rhs: Int) -> Kin {
//        Kin(quarks: lhs.quarks - UInt64(rhs))
//    }
    
    public static func * (lhs: Self, rhs: Int) -> Kin {
        Kin(quarks: lhs.quarks * UInt64(rhs))
    }
    
//    public static func * (lhs: Self, rhs: Self) -> Kin {
//        Kin(quarks: lhs.quarks * rhs.quarks)
//    }
    
//    public static func / (lhs: Self, rhs: Self) -> Kin {
//        Kin(quarks: lhs.quarks / rhs.quarks)
//    }

    public static func / (lhs: Self, rhs: Int) -> Int {
        Int((lhs.quarks / UInt64(rhs)).toKinTruncating)
    }
}

// MARK: - Decimal -

private extension Decimal {
    func roundedUpToNearestQuark() -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, 5, .up)
        return result
    }
    
    func roundedDownToNearestKin() -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, 0, .down)
        return result
    }
}

private extension Decimal {
    
    static var multiplier: Decimal = 100_000
    
    var toQuarks: UInt64 {
        NSDecimalNumber(decimal: self * .multiplier).uint64Value
    }
    
    var toKin: Decimal {
        self / .multiplier
    }
}

private extension UInt64 {
    
    static var multiplier: UInt64 = 100_000
    
    var toQuarks: UInt64 {
        self * .multiplier
    }
    
    var toKin: Decimal {
        Decimal(self) / .multiplier
    }
    
    var toKinTruncating: UInt64 {
        self / .multiplier
    }
}
