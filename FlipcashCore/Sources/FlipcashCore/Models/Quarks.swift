//
//  Quarks.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct Quarks: Equatable, Hashable, Codable, Sendable {

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

    public init(fiatUnsigned: UInt64, currencyCode: CurrencyCode, decimals: Int) {
        self.init(
            quarks: fiatUnsigned.scaleDownInt(decimals),
            currencyCode: currencyCode,
            decimals: decimals
        )
    }

    public static func zero(currencyCode: CurrencyCode, decimals: Int) -> Quarks {
        Quarks(
            quarks: 0 as UInt64,
            currencyCode: currencyCode,
            decimals: decimals
        )
    }

    // MARK: - Operations -

    public func subtracting(_ value: Quarks) throws -> Quarks {
        guard value.currencyCode == currencyCode else {
            throw Error.currencyCodeMismatch
        }

        guard value.decimals == decimals else {
            throw Error.decimalMismatch
        }

        guard quarks >= value.quarks else {
            throw Error.invalidNegativeValue
        }

        return Quarks(
            quarks: quarks - value.quarks,
            currencyCode: currencyCode,
            decimals: decimals
        )
    }
}

// MARK: - Errors -

extension Quarks {
    public enum Error: Swift.Error {
        case invalidNegativeValue
        case currencyCodeMismatch
        case decimalMismatch
    }
}

// MARK: - Display Threshold -

extension Quarks {
    /// Whether this value would format as non-zero in `currencyCode`.
    public var hasDisplayableValue: Bool {
        // Smallest quark count the currency can render (e.g. USD 6-decimal → 10_000).
        let minimum = UInt64(pow(10.0, Double(decimals - currencyCode.maximumFractionDigits)))
        return quarks >= minimum
    }

    /// Non-zero but too small to display (would format as the currency's zero).
    public var isApproximatelyZero: Bool {
        quarks > 0 && !hasDisplayableValue
    }
}

// MARK: - Formatting -

extension Quarks {
    public func formatted(suffix: String? = nil) -> String {
        return NumberFormatter.fiat(
            currency: currencyCode,
            minimumFractionDigits: currencyCode.maximumFractionDigits,
            maximumFractionDigits: currencyCode.maximumFractionDigits,
            truncated: false,
            suffix: suffix
        ).string(from: decimalValue)!
    }
}

// MARK: - Description -

extension Quarks: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        formatted(suffix: nil)
    }

    public var debugDescription: String {
        description
    }
}

// MARK: - Comparable -

extension Quarks: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        guard lhs.currencyCode == rhs.currencyCode else {
            assertionFailure("Attempting to compare different currency Fiat values.")
            return false
        }

        // Compare via decimalValue to avoid UInt64 overflow when scaling quarks
        // up to a common precision (high-rate currencies like CLP, VND, IRR).
        return lhs.decimalValue < rhs.decimalValue
    }
}
